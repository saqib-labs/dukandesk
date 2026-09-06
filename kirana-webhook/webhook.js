const express = require('express');
const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');
const { parseOrderMessage } = require('./orderParser');
const { parseWithLLM } = require('./llmParser');
const { sendOtpEmail, verifyOtpOnly } = require('./emailAuth');
const axios = require('axios');
const { GoogleGenerativeAI } = require('@google/generative-ai');

admin.initializeApp({
  credential: admin.cert(serviceAccount),
});

const db = getFirestore();
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

const app = express();
app.use(express.json());

const VERIFY_TOKEN = "kirana123";
const FREE_ORDER_LIMIT = 50;

// ============================================================
// WhatsApp message sender
// ============================================================

async function sendWhatsAppMessage(toNumber, messageText, senderToken, senderPhoneNumberId) {
  const url = `https://graph.facebook.com/v22.0/${senderPhoneNumberId}/messages`;

  try {
    await axios.post(
      url,
      {
        messaging_product: 'whatsapp',
        to: toNumber,
        type: 'text',
        text: { body: messageText },
      },
      {
        headers: {
          Authorization: `Bearer ${senderToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log(`WhatsApp message sent to ${toNumber}`);
  } catch (error) {
    console.error('Failed to send WhatsApp message:', error.response?.data || error.message);
  }
}

// ============================================================
// Voice note transcription
// ============================================================

async function downloadAndTranscribeVoiceNote(mediaId, senderToken) {
  const mediaInfoRes = await axios.get(
    `https://graph.facebook.com/v22.0/${mediaId}`,
    { headers: { Authorization: `Bearer ${senderToken}` } }
  );

  const mediaUrl = mediaInfoRes.data.url;

  const audioRes = await axios.get(mediaUrl, {
    headers: { Authorization: `Bearer ${senderToken}` },
    responseType: 'arraybuffer',
  });

  const audioBase64 = Buffer.from(audioRes.data).toString('base64');

  const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

  const result = await generateWithRetry(model, [
    { inlineData: { mimeType: 'audio/ogg', data: audioBase64 } },
    {
      text:
        'Transcribe this audio message exactly as spoken. ' +
        'It may be in any language (English, Urdu, Punjabi, Pashto, Roman Punjabi, Roman Urdu, Arabic, Hindi, etc). ' +
        'Respond with ONLY the transcription text, nothing else.',
    },
  ]);

  return result.response.text().trim();
}

async function generateWithRetry(model, input, maxRetries = 2) {
  let lastError;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await model.generateContent(input);
    } catch (err) {
      lastError = err;
      if (err.message?.includes('429')) throw err;
      const isRetryable = err.message?.includes('503') || err.message?.includes('overloaded');
      if (!isRetryable || attempt === maxRetries) throw err;
      const delayMs = 1000 * attempt;
      console.log(`Gemini call failed (attempt ${attempt}/${maxRetries}), retrying in ${delayMs}ms...`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  throw lastError;
}

// ============================================================
// Universal Language detection & translation
// ============================================================

async function detectLanguage(text) {
  try {
    const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });
    const prompt = `Detect the primary language of this text. Respond with ONLY the single language name in English (e.g., "English", "Urdu", "Punjabi", "Pashto", "Arabic", "Hindi").

Guidelines:
- If written in Latin/Roman script with Punjabi words (e.g., "chahida", "kilo", "aata", "tay", "sanu", "pao"), respond with "Punjabi".
- If written in Latin/Roman script with Urdu words (e.g., "chahye", "namak", "chawal", "bhejo"), respond with "Urdu".
- If written in native Punjabi/Urdu/Arabic/Hindi scripts, respond with the exact language name.

Text: "${text}"`;
    const result = await generateWithRetry(model, prompt);
    return result.response.text().trim();
  } catch (err) {
    console.error('Language detection failed after retries:', err.message);
    return 'English';
  }
}

async function translateMessage(text, targetLanguage, rawCustomerText = '') {
  if (!targetLanguage || targetLanguage.toLowerCase() === 'english') return text;
  try {
    const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });
    const prompt = `Translate the following shop response into ${targetLanguage}.

Guidelines:
1. Use natural everyday phrasing.
2. If the target language is Punjabi or Urdu, and the customer originally wrote in Latin/Roman script (e.g., "5 kilo chawal chahye"), respond in natural Roman Punjabi or Roman Urdu script so they can read it easily.
3. Keep product names, numbers, currency amounts (Rs.), unit types (kg, ltr, dozen), and emoji exactly as they are.
4. Respond with ONLY the translated text, nothing else.

Message to translate:
${text}`;

    const result = await generateWithRetry(model, prompt);
    return result.response.text().trim();
  } catch (err) {
    console.error('Translation failed after retries:', err.message);
    return text;
  }
}

// ============================================================
// Product matching
// ============================================================

function findMatchingProduct(productsSnapshot, parsedName) {
  const parsedNameLower = parsedName.toLowerCase();

  for (const doc of productsSnapshot.docs) {
    const product = doc.data();
    const productNameLower = product.name.toLowerCase();

    if (parsedNameLower.includes(productNameLower)) {
      return { id: doc.id, ...product };
    }
    if (productNameLower.includes(parsedNameLower)) {
      return { id: doc.id, ...product };
    }
  }

  return null;
}

// ============================================================
// WhatsApp duplicate-message protection
// ============================================================

async function isWhatsAppMessageAlreadyProcessed(messageId) {
  if (!messageId) {
    console.warn('WhatsApp message has no message ID. Cannot perform duplicate protection.');
    return false;
  }

  const processedRef = db.collection('processedWhatsAppMessages').doc(messageId);

  try {
    const wasAlreadyProcessed = await db.runTransaction(async (transaction) => {
      const processedDoc = await transaction.get(processedRef);

      if (processedDoc.exists) {
        return true;
      }

      transaction.set(processedRef, {
        messageId: messageId,
        processedAt: FieldValue.serverTimestamp(),
      });

      return false;
    });

    return wasAlreadyProcessed;
  } catch (error) {
    console.error('Error checking WhatsApp duplicate message:', error);
    throw error;
  }
}

// ============================================================
// Webhook verification
// ============================================================

app.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === VERIFY_TOKEN) {
    console.log('Webhook verified!');
    res.status(200).send(challenge);
  } else {
    res.sendStatus(403);
  }
});

// ============================================================
// Email OTP
// ============================================================

app.post('/send-email-otp', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email required' });
    await sendOtpEmail(db, email);
    res.json({ success: true });
  } catch (error) {
    console.error('Send OTP error:', error);
    res.status(500).json({ error: error.message });
  }
});

app.post('/verify-email-otp', async (req, res) => {
  try {
    const { email, otp } = req.body;
    if (!email || !otp) return res.status(400).json({ error: 'Email and OTP required' });
    await verifyOtpOnly(db, email, otp);
    res.json({ success: true });
  } catch (error) {
    console.error('Verify OTP error:', error);
    res.status(400).json({ error: error.message });
  }
});

// ============================================================
// WhatsApp Webhook
// ============================================================

app.post('/webhook', (req, res) => {
  res.sendStatus(200);
  processIncomingWebhook(req.body).catch((err) => {
    console.error('Unhandled error in background webhook processing:', err);
  });
});

async function processIncomingWebhook(body) {
  console.log('Incoming message:', JSON.stringify(body, null, 2));

  let messageId;

  try {
    const entry = body.entry?.[0];
    const change = entry?.changes?.[0];

    const incomingPhoneNumberId = change?.value?.metadata?.phone_number_id;
    const messages = change?.value?.messages;

    if (!incomingPhoneNumberId || !messages || messages.length === 0) {
      return;
    }

    const channelDoc = await db.collection('shopChannels').doc(incomingPhoneNumberId).get();

    if (!channelDoc.exists) {
      console.log(`No shop registered for phone_number_id ${incomingPhoneNumberId}`);
      return;
    }

    const channel = channelDoc.data();
    const ownerId = channel.ownerId;
    const shopToken = channel.whatsappToken;
    const shopPhoneNumberId = incomingPhoneNumberId;

    const message = messages[0];
    messageId = message.id;
    const from = message.from;

    if (!messageId) {
      console.warn('Incoming WhatsApp message has no message.id');
    } else {
      console.log(`Checking WhatsApp message ID: ${messageId}`);
      const alreadyProcessed = await isWhatsAppMessageAlreadyProcessed(messageId);
      if (alreadyProcessed) {
        console.log(`Duplicate WhatsApp message ignored: ${messageId}`);
        return;
      }
      console.log(`New WhatsApp message accepted: ${messageId}`);
    }

    let text = message.text?.body || '';

    if (message.type === 'audio' && message.audio?.id) {
      console.log('Received voice note, transcribing...');
      try {
        text = await downloadAndTranscribeVoiceNote(message.audio.id, shopToken);
        console.log(`Transcribed voice note: "${text}"`);
      } catch (err) {
        console.error('Voice transcription failed:', err.message);
        const isQuotaError = err.message?.includes('429');
        const failMsg = isQuotaError
          ? "Sorry, we're experiencing high demand right now. Please try again in a minute, or type your order instead."
          : "Sorry, I couldn't understand your voice message. Please try typing your order instead.";
        await sendWhatsAppMessage(from, failMsg, shopToken, shopPhoneNumberId);
        if (messageId) await db.collection('processedWhatsAppMessages').doc(messageId).delete();
        return;
      }
    }

    if (!text) {
      return;
    }

    let customerLanguage = await detectLanguage(text);
    console.log(`Detected customer language: ${customerLanguage}`);

    async function replyToCustomer(to, msg) {
      if (!customerLanguage || customerLanguage.toLowerCase() === 'english') {
        await sendWhatsAppMessage(to, msg, shopToken, shopPhoneNumberId);
        return;
      }
      const translated = await translateMessage(msg, customerLanguage, text);
      await sendWhatsAppMessage(to, translated, shopToken, shopPhoneNumberId);
    }

    const lowerText = text.trim().toLowerCase();

    if (['points', 'loyalty', 'my points'].includes(lowerText)) {
      const loyaltyDoc = await db.collection('loyaltyPoints').doc(from).get();
      const points = loyaltyDoc.exists ? loyaltyDoc.data().points || 0 : 0;
      await replyToCustomer(from, `⭐ You have ${points} loyalty points! (Rs. 100 spent = 1 point)`);
      return;
    }

    if (['history', 'my orders', 'orders'].includes(lowerText)) {
      const recentOrders = await db
        .collection('orders')
        .where('ownerId', '==', ownerId)
        .where('customerNumber', '==', from)
        .where('status', '==', 'matched')
        .orderBy('createdAt', 'desc')
        .limit(5)
        .get();

      if (recentOrders.empty) {
        await replyToCustomer(from, "You don't have any past orders with us yet.");
      } else {
        let reply = '📋 Your recent orders:\n\n';
        recentOrders.docs.forEach((doc, i) => {
          const data = doc.data();
          const items = (data.matchedItems || [])
            .map((item) => `${item.quantity} ${item.unit} ${item.productName}`)
            .join(', ');
          const date = data.createdAt?.toDate();
          reply += `${i + 1}. ${items} (${date ? date.toLocaleDateString('en-GB') : ''})\n`;
        });
        reply += '\nType "repeat" to reorder your last order.';
        await replyToCustomer(from, reply);
      }
      return;
    }

    if (['balance', 'credit', 'udhaar'].includes(lowerText)) {
      const creditSnapshot = await db
        .collection('creditTransactions')
        .where('ownerId', '==', ownerId)
        .where('phone', '==', from)
        .get();

      let balance = 0;
      creditSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        balance += data.type === 'credit' ? data.amount : -data.amount;
      });

      const msg = balance <= 0
        ? '✅ You have no outstanding balance with us.'
        : `💰 Your outstanding balance is Rs. ${balance.toFixed(0)}.`;
      await replyToCustomer(from, msg);
      return;
    }

    if (['repeat', 'same as last time', 'reorder'].includes(lowerText)) {
      const lastOrderSnapshot = await db
        .collection('orders')
        .where('ownerId', '==', ownerId)
        .where('customerNumber', '==', from)
        .where('status', '==', 'matched')
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();

      if (lastOrderSnapshot.empty) {
        await replyToCustomer(from, "You don't have a previous order to repeat.");
        return;
      }

      const lastOrder = lastOrderSnapshot.docs[0].data();
      const items = lastOrder.matchedItems || [];

      if (items.length === 0) {
        await replyToCustomer(from, "Couldn't find items from your last order.");
        return;
      }

      text = items.map((item) => `${item.quantity}${item.unit} ${item.productName}`).join(' and ');
      console.log(`Repeat order reconstructed as: "${text}"`);
    } else {
      const availabilityMatch = lowerText.match(/^(do you have|have you got|is .* available|available)\s*(.*)/i);

      if (availabilityMatch || lowerText.startsWith('have ')) {
        const searchTerm = (availabilityMatch ? availabilityMatch[2] : lowerText.replace('have', ''))
          .replace(/[?.!]/g, '')
          .trim();

        if (searchTerm.length > 1) {
          const productsSnapshotCheck = await db.collection('products').where('ownerId', '==', ownerId).get();

          const match = productsSnapshotCheck.docs.find(
            (doc) =>
              doc.data().name.toLowerCase().includes(searchTerm) ||
              searchTerm.includes(doc.data().name.toLowerCase())
          );

          if (match) {
            const p = match.data();
            const inStock = p.stockQty > 0;
            await replyToCustomer(
              from,
              inStock
                ? `✅ Yes! ${p.name} is available - Rs. ${p.price} per ${p.unit}. ${p.stockQty} ${p.unit} in stock.`
                : `❌ Sorry, ${p.name} is currently out of stock.`
            );
          } else {
            await replyToCustomer(from, `Sorry, we don't carry "${searchTerm}" right now.`);
          }
          return;
        }
      }
    }

    const userDoc = await db.collection('users').doc(ownerId).get();
    const isPremium = userDoc.exists && userDoc.data()?.isPremium === true;

    if (!isPremium) {
      const startOfMonth = new Date();
      startOfMonth.setDate(1);
      startOfMonth.setHours(0, 0, 0, 0);

      const monthlyOrdersSnapshot = await db
        .collection('orders')
        .where('ownerId', '==', ownerId)
        .where('createdAt', '>=', startOfMonth)
        .get();

      if (monthlyOrdersSnapshot.size >= FREE_ORDER_LIMIT) {
        await replyToCustomer(
          from,
          `Sorry, this shop has reached its monthly order limit on the free plan. Please contact the shop owner directly.`
        );
        return;
      }
    }

    let parsed = parseOrderMessage(text);
    console.log('Rule-based parsed result:', JSON.stringify(parsed, null, 2));

    const productsSnapshot = await db.collection('products').where('ownerId', '==', ownerId).get();
    const productNames = productsSnapshot.docs.map((doc) => doc.data().name);

    if (parsed.success) {
      const anyItemLooksReal = parsed.items.some(
        (item) => findMatchingProduct(productsSnapshot, item.productName) !== null
      );
      if (!anyItemLooksReal) {
        console.log('Rule-based match looked bogus, forcing LLM fallback...');
        parsed = { success: false, rawText: text };
      }
    }

    if (!parsed.success) {
      console.log('Falling back to LLM parsing...');
      const llmResult = await parseWithLLM(text, productNames);
      console.log('LLM result:', JSON.stringify(llmResult, null, 2));

      if (llmResult.language) {
        customerLanguage = llmResult.language;
        console.log(`Language from LLM: ${customerLanguage}`);
      }

      if (llmResult.isOrder && llmResult.items.length > 0) {
        parsed = { success: true, items: llmResult.items, partialFailure: false, failedSegments: [] };
      }
    }

    if (!parsed.success) {
      await replyToCustomer(
        from,
        `Sorry, we couldn't understand your order. Please try a format like "2kg rice" or "1 dozen eggs", or call the shop directly.`
      );

      await db.collection('orders').add({
        ownerId,
        customerNumber: from,
        rawMessage: text,
        status: 'unparsed',
        createdAt: FieldValue.serverTimestamp(),
        whatsappMessageId: messageId || null,
      });
      return;
    }

    const matchedItems = [];
    const notFoundItems = [];

    for (const item of parsed.items) {
      const matchedProduct = findMatchingProduct(productsSnapshot, item.productName);

      if (matchedProduct) {
        const newStock = matchedProduct.stockQty - item.quantity;
        await db.collection('products').doc(matchedProduct.id).update({ stockQty: newStock });
        console.log(`Stock updated: ${matchedProduct.name} ${matchedProduct.stockQty} -> ${newStock}`);

        const LARGE_ORDER_THRESHOLD = 5000;
        const itemTotalValue = item.quantity * matchedProduct.price;

        if (itemTotalValue >= LARGE_ORDER_THRESHOLD) {
          await sendWhatsAppMessage(
            channel.displayPhoneNumber,
            `🔔 Large Order Alert: ${from} ordered ${item.quantity} ${matchedProduct.unit} ${matchedProduct.name} (worth Rs. ${itemTotalValue.toFixed(0)}). Please verify.`,
            shopToken,
            shopPhoneNumberId
          );
        }

        if (newStock < 0) {
          await sendWhatsAppMessage(
            channel.displayPhoneNumber,
            `🚨 Stock Discrepancy: ${matchedProduct.name} went negative (${newStock} ${matchedProduct.unit}).`,
            shopToken,
            shopPhoneNumberId
          );
        }

        matchedItems.push({ productName: matchedProduct.name, quantity: item.quantity, unit: item.unit });

        if (newStock <= matchedProduct.lowStockThreshold) {
          await sendWhatsAppMessage(
            channel.displayPhoneNumber,
            `⚠️ Low Stock Alert: ${matchedProduct.name} is down to ${newStock} ${matchedProduct.unit}. Time to restock!`,
            shopToken,
            shopPhoneNumberId
          );
        }

        const itemValue = item.quantity * matchedProduct.price;
        const pointsEarned = Math.floor(itemValue / 100);

        if (pointsEarned > 0) {
          const loyaltyRef = db.collection('loyaltyPoints').doc(from);
          const loyaltyDoc = await loyaltyRef.get();
          const currentPoints = loyaltyDoc.exists ? loyaltyDoc.data().points || 0 : 0;
          await loyaltyRef.set(
            { points: currentPoints + pointsEarned, lastUpdated: FieldValue.serverTimestamp() },
            { merge: true }
          );
        }
      } else {
        notFoundItems.push(item.productName);
      }
    }

    await db.collection('orders').add({
      ownerId,
      customerNumber: from,
      rawMessage: text,
      matchedItems,
      notFoundItems,
      unparsedSegments: parsed.failedSegments || [],
      status: matchedItems.length > 0 ? 'matched' : 'unmatched',
      createdAt: FieldValue.serverTimestamp(),
      whatsappMessageId: messageId || null,
    });

    let replyLines = [];

    if (matchedItems.length > 0) {
      replyLines.push('✅ Order received:');
      matchedItems.forEach((item) => replyLines.push(`- ${item.quantity} ${item.unit} ${item.productName}`));

      const loyaltyDoc = await db.collection('loyaltyPoints').doc(from).get();
      if (loyaltyDoc.exists) {
        replyLines.push(`\n⭐ You now have ${loyaltyDoc.data().points || 0} loyalty points!`);
      }
    }

    if (notFoundItems.length > 0) {
      replyLines.push(`\n⚠️ Not found in our shop: ${notFoundItems.join(', ')}`);
    }

    if (parsed.failedSegments?.length > 0) {
      replyLines.push(`\nCouldn't understand: "${parsed.failedSegments.join(', ')}"`);
    }

    if (matchedItems.length === 0 && notFoundItems.length === 0) {
      replyLines.push(`Sorry, we couldn't understand your order. Please try again.`);
    }

    await replyToCustomer(from, replyLines.join('\n'));

    console.log(`Order from ${from} (shop: ${ownerId}): matched ${matchedItems.length}, not found ${notFoundItems.length}`);
    console.log(`WhatsApp message ${messageId} processed successfully.`);
  } catch (error) {
    console.error('Error processing order:', error);
    if (messageId) {
      try {
        await db.collection('processedWhatsAppMessages').doc(messageId).delete();
        console.log(`Released reservation for failed message ${messageId}, can be retried.`);
      } catch (cleanupError) {
        console.error('Failed to release message reservation:', cleanupError);
      }
    }
  }
}

// ============================================================
// Broadcast listener - per shop
// ============================================================

db.collection('broadcasts').where('status', '==', 'pending').onSnapshot(async (snapshot) => {
  for (const change of snapshot.docChanges()) {
    if (change.type === 'added') {
      const broadcast = change.doc.data();
      const broadcastId = change.doc.id;

      const channelsSnapshot = await db.collection('shopChannels').where('ownerId', '==', broadcast.ownerId).get();
      if (channelsSnapshot.empty) continue;

      const channel = channelsSnapshot.docs[0].data();

      console.log(`Processing broadcast for shop ${broadcast.ownerId} to ${broadcast.targetPhones.length} customers...`);
      for (const phone of broadcast.targetPhones) {
        await sendWhatsAppMessage(phone, broadcast.message, channel.whatsappToken, channelsSnapshot.docs[0].id);
      }

      await db.collection('broadcasts').doc(broadcastId).update({ status: 'sent' });
    }
  }
});

// ============================================================
// Start server
// ============================================================

app.listen(5001, () => console.log('Webhook listening on port 5001'));