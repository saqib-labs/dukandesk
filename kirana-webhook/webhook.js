const express = require('express');
const cors = require('cors');
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

// ============================================================
// CORS
// ============================================================
// Allows Flutter Web frontend to communicate with this backend.
// After Firebase Hosting deployment, set FRONTEND_URL in Render
// to your Firebase Hosting URL.
// ============================================================

app.use(
  cors({
    origin: process.env.FRONTEND_URL || true,
  })
);

const VERIFY_TOKEN = process.env.VERIFY_TOKEN || 'kirana123';
const FREE_ORDER_LIMIT = 50;

// ============================================================
// WhatsApp message sender
// ============================================================

async function sendWhatsAppMessage(
  toNumber,
  messageText,
  senderToken,
  senderPhoneNumberId
) {
  const url = `https://graph.facebook.com/v22.0/${senderPhoneNumberId}/messages`;

  try {
    await axios.post(
      url,
      {
        messaging_product: 'whatsapp',
        to: toNumber,
        type: 'text',
        text: {
          body: messageText,
        },
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
    console.error(
      'Failed to send WhatsApp message:',
      error.response?.data || error.message
    );
  }
}

// ============================================================
// Voice note transcription
// ============================================================

async function downloadAndTranscribeVoiceNote(
  mediaId,
  senderToken,
  mimeType = 'audio/ogg'
) {
  const mediaInfoRes = await axios.get(
    `https://graph.facebook.com/v22.0/${mediaId}`,
    {
      headers: {
        Authorization: `Bearer ${senderToken}`,
      },
    }
  );

  const mediaUrl = mediaInfoRes.data.url;

  const audioRes = await axios.get(mediaUrl, {
    headers: {
      Authorization: `Bearer ${senderToken}`,
    },
    responseType: 'arraybuffer',
  });

  const audioBase64 = Buffer.from(audioRes.data).toString('base64');

  const safeMimeType = (mimeType || 'audio/ogg')
    .split(';')[0]
    .trim();

  console.log(
    `Downloaded voice media ${mediaId}: ${audioRes.data.length} bytes, MIME type: ${safeMimeType}`
  );

  const model = genAI.getGenerativeModel({
    model: 'gemini-flash-latest',
  });

  const result = await generateWithRetry(model, [
    {
      inlineData: {
        mimeType: safeMimeType,
        data: audioBase64,
      },
    },
    {
      text:
        'Transcribe this audio message exactly as spoken. ' +
        'It may be in any language (English, Urdu, Punjabi, Pashto, Roman Urdu, etc). ' +
        'Respond with ONLY the transcription text, nothing else.',
    },
  ]);

  return result.response.text().trim();
}

// ============================================================
// Gemini retry helper
// ============================================================

async function generateWithRetry(model, input, maxRetries = 2) {
  let lastError;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await model.generateContent(input);
    } catch (err) {
      lastError = err;

      // 429 = quota exhausted
      // Retrying immediately will generally not help.
      if (err.message?.includes('429')) {
        throw err;
      }

      const isRetryable =
        err.message?.includes('503') ||
        err.message?.includes('overloaded');

      if (!isRetryable || attempt === maxRetries) {
        throw err;
      }

      const delayMs = 1000 * attempt;

      console.log(
        `Gemini call failed (attempt ${attempt}/${maxRetries}), retrying in ${delayMs}ms...`
      );

      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  throw lastError;
}

// ============================================================
// Language detection
// ============================================================

async function detectLanguage(text) {
  try {
    const model = genAI.getGenerativeModel({
      model: 'gemini-flash-latest',
    });

    const prompt = `
Detect the language of this text.

Respond with ONLY the language name in English.

Examples:
English
Urdu
Punjabi
Pashto
Arabic
Hindi

If the text is mixed or unclear, choose the dominant language.

Text:
"${text}"
`;

    const result = await generateWithRetry(model, prompt);

    return result.response.text().trim();
  } catch (err) {
    console.error(
      'Language detection failed after retries:',
      err.message
    );

    return 'English';
  }
}

// ============================================================
// Translation
// ============================================================

async function translateMessage(text, targetLanguage) {
  if (
    !targetLanguage ||
    targetLanguage.toLowerCase() === 'english'
  ) {
    return text;
  }

  try {
    const model = genAI.getGenerativeModel({
      model: 'gemini-flash-latest',
    });

    const prompt = `
Translate the following message into ${targetLanguage}.

Use natural everyday phrasing, not overly formal language.

Keep:
- Product names
- Numbers
- Currency amounts
- Emoji

exactly as they are.

Respond with ONLY the translated text.

Text:
${text}
`;

    const result = await generateWithRetry(model, prompt);

    return result.response.text().trim();
  } catch (err) {
    console.error(
      'Translation failed after retries:',
      err.message
    );

    return text;
  }
}

// ============================================================
// Product matching
// ============================================================

function findMatchingProduct(productsSnapshot, parsedName) {
  if (!parsedName) {
    return null;
  }

  const parsedNameLower = parsedName.toLowerCase().trim();

  for (const doc of productsSnapshot.docs) {
    const product = doc.data();

    if (!product.name) {
      continue;
    }

    const productNameLower = product.name
      .toLowerCase()
      .trim();

    if (parsedNameLower.includes(productNameLower)) {
      return {
        id: doc.id,
        ...product,
      };
    }

    if (productNameLower.includes(parsedNameLower)) {
      return {
        id: doc.id,
        ...product,
      };
    }
  }

  return null;
}

// ============================================================
// WhatsApp duplicate-message protection
// ============================================================

async function isWhatsAppMessageAlreadyProcessed(messageId) {
  if (!messageId) {
    console.warn(
      'WhatsApp message has no message ID. Cannot perform duplicate protection.'
    );

    return false;
  }

  const processedRef = db
    .collection('processedWhatsAppMessages')
    .doc(messageId);

  try {
    const wasAlreadyProcessed = await db.runTransaction(
      async (transaction) => {
        const processedDoc = await transaction.get(processedRef);

        if (processedDoc.exists) {
          return true;
        }

        transaction.set(processedRef, {
          messageId: messageId,
          processedAt: FieldValue.serverTimestamp(),
        });

        return false;
      }
    );

    return wasAlreadyProcessed;
  } catch (error) {
    console.error(
      'Error checking WhatsApp duplicate message:',
      error
    );

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

  if (
    mode === 'subscribe' &&
    token === VERIFY_TOKEN
  ) {
    console.log('Webhook verified!');

    return res.status(200).send(challenge);
  }

  console.log('Webhook verification failed.');

  return res.sendStatus(403);
});

// ============================================================
// Email OTP
// ============================================================

app.post('/send-email-otp', async (req, res) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({
        error: 'Email required',
      });
    }

    await sendOtpEmail(db, email);

    return res.json({
      success: true,
    });
  } catch (error) {
    console.error('Send OTP error:', error);

    return res.status(500).json({
      error: error.message,
    });
  }
});

// ============================================================
// Verify Email OTP
// ============================================================

app.post('/verify-email-otp', async (req, res) => {
  try {
    const { email, otp } = req.body;

    if (!email || !otp) {
      return res.status(400).json({
        error: 'Email and OTP required',
      });
    }

    await verifyOtpOnly(db, email, otp);

    return res.json({
      success: true,
    });
  } catch (error) {
    console.error('Verify OTP error:', error);

    return res.status(400).json({
      error: error.message,
    });
  }
});

// ============================================================
// Process incoming WhatsApp message
// ============================================================

async function processIncomingWhatsAppMessage(
  message,
  channel
) {
  const ownerId = channel.ownerId;
  const shopToken = channel.whatsappToken;
  const shopPhoneNumberId = channel.phoneNumberId;

  const messageId = message.id;
  const from = message.from;

  // ==========================================================
  // DUPLICATE PROTECTION
  // ==========================================================

  if (!messageId) {
    console.warn(
      'Incoming WhatsApp message has no message.id. Processing without duplicate protection.'
    );
  } else {
    console.log(
      `Checking WhatsApp message ID: ${messageId}`
    );

    const alreadyProcessed =
      await isWhatsAppMessageAlreadyProcessed(
        messageId
      );

    if (alreadyProcessed) {
      console.log(
        `Duplicate WhatsApp message ignored: ${messageId}`
      );

      return;
    }

    console.log(
      `New WhatsApp message accepted: ${messageId}`
    );
  }

  try {
    // ========================================================
    // Accept different WhatsApp message types
    // ========================================================

    let text =
      message.text?.body ||
      message.interactive?.button_reply?.title ||
      message.interactive?.list_reply?.title ||
      message.button?.text ||
      message.image?.caption ||
      message.document?.caption ||
      '';

    // ========================================================
    // Voice message
    // ========================================================

    if (
      message.type === 'audio' &&
      message.audio?.id
    ) {
      console.log(
        'Received voice note, transcribing...'
      );

      try {
        text =
          await downloadAndTranscribeVoiceNote(
            message.audio.id,
            shopToken,
            message.audio.mime_type
          );

        console.log(
          `Transcribed voice note: "${text}"`
        );
      } catch (err) {
        console.error(
          'Voice transcription failed:',
          err.message
        );

        await sendWhatsAppMessage(
          from,
          "Sorry, I couldn't understand your voice message. Please try typing your order instead.",
          shopToken,
          shopPhoneNumberId
        );

        return;
      }
    }

    if (!text) {
      console.log(
        'Message contained no usable text.'
      );

      return;
    }

    // ========================================================
    // Customer language
    // ========================================================

    let customerLanguage = 'English';

    async function replyToCustomer(to, msg) {
      if (
        !customerLanguage ||
        customerLanguage.toLowerCase() === 'english'
      ) {
        await sendWhatsAppMessage(
          to,
          msg,
          shopToken,
          shopPhoneNumberId
        );

        return;
      }

      const translated =
        await translateMessage(
          msg,
          customerLanguage
        );

      await sendWhatsAppMessage(
        to,
        translated,
        shopToken,
        shopPhoneNumberId
      );
    }

    const lowerText = text
      .trim()
      .toLowerCase();

    // ========================================================
    // Loyalty points
    // ========================================================

    if (
      [
        'points',
        'loyalty',
        'my points',
      ].includes(lowerText)
    ) {
      const loyaltyDoc = await db
        .collection('loyaltyPoints')
        .doc(from)
        .get();

      const points = loyaltyDoc.exists
        ? loyaltyDoc.data().points || 0
        : 0;

      await replyToCustomer(
        from,
        `⭐ You have ${points} loyalty points! (Rs. 100 spent = 1 point)`
      );

      return;
    }

    // ========================================================
    // Order history
    // ========================================================

    if (
      [
        'history',
        'my orders',
        'orders',
      ].includes(lowerText)
    ) {
      const recentOrders = await db
        .collection('orders')
        .where('ownerId', '==', ownerId)
        .where('customerNumber', '==', from)
        .where('status', '==', 'matched')
        .orderBy('createdAt', 'desc')
        .limit(5)
        .get();

      if (recentOrders.empty) {
        await replyToCustomer(
          from,
          "You don't have any past orders with us yet."
        );
      } else {
        let reply =
          '📋 Your recent orders:\n\n';

        recentOrders.docs.forEach(
          (doc, i) => {
            const data = doc.data();

            const items =
              (data.matchedItems || [])
                .map(
                  (item) =>
                    `${item.quantity} ${item.unit} ${item.productName}`
                )
                .join(', ');

            const date =
              data.createdAt?.toDate();

            reply +=
              `${i + 1}. ${items} ` +
              `(${date ? date.toLocaleDateString('en-GB') : ''})\n`;
          }
        );

        reply +=
          '\nType "repeat" to reorder your last order.';

        await replyToCustomer(
          from,
          reply
        );
      }

      return;
    }

    // ========================================================
    // Credit / Udhaar balance
    // ========================================================

    if (
      [
        'balance',
        'credit',
        'udhaar',
      ].includes(lowerText)
    ) {
      const creditSnapshot = await db
        .collection('creditTransactions')
        .where('ownerId', '==', ownerId)
        .where('phone', '==', from)
        .get();

      let balance = 0;

      creditSnapshot.docs.forEach(
        (doc) => {
          const data = doc.data();

          balance +=
            data.type === 'credit'
              ? data.amount
              : -data.amount;
        }
      );

      const msg =
        balance <= 0
          ? '✅ You have no outstanding balance with us.'
          : `💰 Your outstanding balance is Rs. ${balance.toFixed(0)}.`;

      await replyToCustomer(
        from,
        msg
      );

      return;
    }

    // ========================================================
    // Repeat last order
    // ========================================================

    if (
      [
        'repeat',
        'same as last time',
        'reorder',
      ].includes(lowerText)
    ) {
      const lastOrderSnapshot =
        await db
          .collection('orders')
          .where('ownerId', '==', ownerId)
          .where(
            'customerNumber',
            '==',
            from
          )
          .where(
            'status',
            '==',
            'matched'
          )
          .orderBy(
            'createdAt',
            'desc'
          )
          .limit(1)
          .get();

      if (lastOrderSnapshot.empty) {
        await replyToCustomer(
          from,
          "You don't have a previous order to repeat."
        );

        return;
      }

      const lastOrder =
        lastOrderSnapshot.docs[0].data();

      const items =
        lastOrder.matchedItems || [];

      if (items.length === 0) {
        await replyToCustomer(
          from,
          "Couldn't find items from your last order."
        );

        return;
      }

      text = items
        .map(
          (item) =>
            `${item.quantity}${item.unit} ${item.productName}`
        )
        .join(' and ');

      console.log(
        `Repeat order reconstructed as: "${text}"`
      );
    } else {
      // ======================================================
      // Product availability
      // ======================================================

      const availabilityMatch =
        lowerText.match(
          /^(do you have|have you got|is .* available|available)\s*(.*)/i
        );

      if (
        availabilityMatch ||
        lowerText.startsWith('have ')
      ) {
        const searchTerm = (
          availabilityMatch
            ? availabilityMatch[2]
            : lowerText.replace('have', '')
        )
          .replace(/[?.!]/g, '')
          .trim();

        if (searchTerm.length > 1) {
          const productsSnapshotCheck =
            await db
              .collection('products')
              .where(
                'ownerId',
                '==',
                ownerId
              )
              .get();

          const match =
            productsSnapshotCheck.docs.find(
              (doc) => {
                const product =
                  doc.data();

                if (!product.name) {
                  return false;
                }

                const productName =
                  product.name.toLowerCase();

                return (
                  productName.includes(
                    searchTerm
                  ) ||
                  searchTerm.includes(
                    productName
                  )
                );
              }
            );

          if (match) {
            const p = match.data();

            const inStock =
              p.stockQty > 0;

            await replyToCustomer(
              from,
              inStock
                ? `✅ Yes! ${p.name} is available - Rs. ${p.price} per ${p.unit}. ${p.stockQty} ${p.unit} in stock.`
                : `❌ Sorry, ${p.name} is currently out of stock.`
            );
          } else {
            await replyToCustomer(
              from,
              `Sorry, we don't carry "${searchTerm}" right now.`
            );
          }

          return;
        }
      }
    }

    // ========================================================
    // Free plan order limit
    // ========================================================

    const userDoc = await db
      .collection('users')
      .doc(ownerId)
      .get();

    const isPremium =
      userDoc.exists &&
      userDoc.data()?.isPremium === true;

    if (!isPremium) {
      const startOfMonth =
        new Date();

      startOfMonth.setDate(1);
      startOfMonth.setHours(
        0,
        0,
        0,
        0
      );

      const monthlyOrdersSnapshot =
        await db
          .collection('orders')
          .where(
            'ownerId',
            '==',
            ownerId
          )
          .where(
            'createdAt',
            '>=',
            startOfMonth
          )
          .get();

      if (
        monthlyOrdersSnapshot.size >=
        FREE_ORDER_LIMIT
      ) {
        await replyToCustomer(
          from,
          `Sorry, this shop has reached its monthly order limit on the free plan. Please contact the shop owner directly.`
        );

        return;
      }
    }

    // ========================================================
    // Order parsing
    // ========================================================

    let parsed =
      parseOrderMessage(text);

    console.log(
      'Rule-based parsed result:',
      JSON.stringify(
        parsed,
        null,
        2
      )
    );

    const productsSnapshot =
      await db
        .collection('products')
        .where(
          'ownerId',
          '==',
          ownerId
        )
        .get();

    const productNames =
      productsSnapshot.docs
        .map(
          (doc) =>
            doc.data().name
        )
        .filter(Boolean);

    // ========================================================
    // Validate rule-based parser
    // ========================================================

    if (parsed.success) {
      const anyItemLooksReal =
        parsed.items.some(
          (item) =>
            findMatchingProduct(
              productsSnapshot,
              item.productName
            ) !== null
        );

      if (!anyItemLooksReal) {
        console.log(
          'Rule-based match looked bogus, forcing LLM fallback...'
        );

        parsed = {
          success: false,
          rawText: text,
        };
      }
    }

    // ========================================================
    // Gemini LLM fallback
    // ========================================================

    if (!parsed.success) {
      console.log(
        'Falling back to LLM parsing...'
      );

      const llmResult =
        await parseWithLLM(
          text,
          productNames
        );

      console.log(
        'LLM result:',
        JSON.stringify(
          llmResult,
          null,
          2
        )
      );

      if (llmResult.language) {
        customerLanguage =
          llmResult.language;

        console.log(
          `Language from LLM: ${customerLanguage}`
        );
      }

      if (
        llmResult.isOrder &&
        llmResult.items &&
        llmResult.items.length > 0
      ) {
        parsed = {
          success: true,
          items: llmResult.items,
          partialFailure: false,
          failedSegments: [],
        };
      }
    }

    // ========================================================
    // Could not understand order
    // ========================================================

    if (!parsed.success) {
      await replyToCustomer(
        from,
        `Sorry, we couldn't understand your order. Please try a format like "2kg rice" or "1 dozen eggs", or call the shop directly.`
      );

      await db
        .collection('orders')
        .add({
          ownerId,
          customerNumber: from,
          rawMessage: text,
          status: 'unparsed',
          createdAt:
            FieldValue.serverTimestamp(),
          whatsappMessageId:
            messageId || null,
        });

      return;
    }

    // ========================================================
    // Match products and update stock
    // ========================================================

    const matchedItems = [];
    const notFoundItems = [];

    for (const item of parsed.items) {
      const matchedProduct =
        findMatchingProduct(
          productsSnapshot,
          item.productName
        );

      if (matchedProduct) {
        const currentStock =
          Number(
            matchedProduct.stockQty || 0
          );

        const quantity =
          Number(
            item.quantity || 0
          );

        const newStock =
          currentStock - quantity;

        // ====================================================
        // Update stock
        // ====================================================

        await db
          .collection('products')
          .doc(matchedProduct.id)
          .update({
            stockQty: newStock,
          });

        console.log(
          `Stock updated: ${matchedProduct.name} ${currentStock} -> ${newStock}`
        );

        // ====================================================
        // Large order alert
        // ====================================================

        const LARGE_ORDER_THRESHOLD =
          5000;

        const itemTotalValue =
          quantity *
          Number(
            matchedProduct.price || 0
          );

        if (
          itemTotalValue >=
          LARGE_ORDER_THRESHOLD
        ) {
          await sendWhatsAppMessage(
            channel.displayPhoneNumber,
            `🔔 Large Order Alert: ${from} ordered ${quantity} ${matchedProduct.unit} ${matchedProduct.name} (worth Rs. ${itemTotalValue.toFixed(0)}). Please verify.`,
            shopToken,
            shopPhoneNumberId
          );
        }

        // ====================================================
        // Negative stock alert
        // ====================================================

        if (newStock < 0) {
          await sendWhatsAppMessage(
            channel.displayPhoneNumber,
            `🚨 Stock Discrepancy: ${matchedProduct.name} went negative (${newStock} ${matchedProduct.unit}).`,
            shopToken,
            shopPhoneNumberId
          );
        }

        // ====================================================
        // Add matched item
        // ====================================================

        matchedItems.push({
          productName:
            matchedProduct.name,
          quantity:
            quantity,
          unit:
            item.unit ||
            matchedProduct.unit,
        });

        // ====================================================
        // Low stock alert
        // ====================================================

        const lowStockThreshold =
          Number(
            matchedProduct.lowStockThreshold ||
              0
          );

        if (
          newStock <=
          lowStockThreshold
        ) {
          await sendWhatsAppMessage(
            channel.displayPhoneNumber,
            `⚠️ Low Stock Alert: ${matchedProduct.name} is down to ${newStock} ${matchedProduct.unit}. Time to restock!`,
            shopToken,
            shopPhoneNumberId
          );
        }

        // ====================================================
        // Loyalty points
        // ====================================================

        const itemValue =
          quantity *
          Number(
            matchedProduct.price || 0
          );

        const pointsEarned =
          Math.floor(
            itemValue / 100
          );

        if (
          pointsEarned > 0
        ) {
          const loyaltyRef =
            db
              .collection(
                'loyaltyPoints'
              )
              .doc(from);

          const loyaltyDoc =
            await loyaltyRef.get();

          const currentPoints =
            loyaltyDoc.exists
              ? loyaltyDoc.data()
                  .points || 0
              : 0;

          await loyaltyRef.set(
            {
              points:
                currentPoints +
                pointsEarned,

              lastUpdated:
                FieldValue.serverTimestamp(),
            },
            {
              merge: true,
            }
          );
        }
      } else {
        notFoundItems.push(
          item.productName
        );
      }
    }

    // ========================================================
    // Create order
    // ========================================================

    await db
      .collection('orders')
      .add({
        ownerId,

        customerNumber:
          from,

        rawMessage:
          text,

        matchedItems:
          matchedItems,

        notFoundItems:
          notFoundItems,

        unparsedSegments:
          parsed.failedSegments ||
          [],

        status:
          matchedItems.length > 0
            ? 'matched'
            : 'unmatched',

        createdAt:
          FieldValue.serverTimestamp(),

        whatsappMessageId:
          messageId || null,
      });

    // ========================================================
    // WhatsApp confirmation
    // ========================================================

    const replyLines = [];

    if (
      matchedItems.length > 0
    ) {
      replyLines.push(
        '✅ Order received:'
      );

      matchedItems.forEach(
        (item) => {
          replyLines.push(
            `- ${item.quantity} ${item.unit} ${item.productName}`
          );
        }
      );

      const loyaltyDoc =
        await db
          .collection(
            'loyaltyPoints'
          )
          .doc(from)
          .get();

      if (
        loyaltyDoc.exists
      ) {
        replyLines.push(
          `\n⭐ You now have ${loyaltyDoc.data().points || 0} loyalty points!`
        );
      }
    }

    if (
      notFoundItems.length > 0
    ) {
      replyLines.push(
        `\n⚠️ Not found in our shop: ${notFoundItems.join(', ')}`
      );
    }

    if (
      parsed.failedSegments &&
      parsed.failedSegments.length > 0
    ) {
      replyLines.push(
        `\nCouldn't understand: "${parsed.failedSegments.join(', ')}"`
      );
    }

    if (
      matchedItems.length === 0 &&
      notFoundItems.length === 0
    ) {
      replyLines.push(
        'Sorry, we couldn\'t understand your order. Please try again.'
      );
    }

    await replyToCustomer(
      from,
      replyLines.join('\n')
    );

    console.log(
      `Order from ${from} (shop: ${ownerId}): matched ${matchedItems.length}, not found ${notFoundItems.length}`
    );

    console.log(
      `WhatsApp message ${messageId} processed successfully.`
    );
  } catch (error) {
    console.error(
      `Error processing WhatsApp message ${
        messageId || '(no-id)'
      }:`,
      error
    );

    // ========================================================
    // Release duplicate reservation after genuine failure
    // ========================================================

    if (messageId) {
      try {
        await db
          .collection(
            'processedWhatsAppMessages'
          )
          .doc(messageId)
          .delete();

        console.log(
          `Released reservation for failed message ${messageId}; retry is allowed.`
        );
      } catch (cleanupError) {
        console.error(
          `Failed to release reservation for ${messageId}:`,
          cleanupError
        );
      }
    }
  }
}

// ============================================================
// WhatsApp POST Webhook
// ============================================================

app.post('/webhook', async (req, res) => {
  console.log(
    'Incoming WhatsApp webhook:',
    JSON.stringify(
      req.body,
      null,
      2
    )
  );

  try {
    const entry =
      req.body.entry?.[0];

    const change =
      entry?.changes?.[0];

    const value =
      change?.value;

    const incomingPhoneNumberId =
      value?.metadata
        ?.phone_number_id;

    const messages =
      value?.messages;

    // ========================================================
    // No messages
    // ========================================================

    if (
      !incomingPhoneNumberId ||
      !Array.isArray(messages) ||
      messages.length === 0
    ) {
      console.log(
        'Webhook event contains no messages. Acknowledging.'
      );

      return res.sendStatus(200);
    }

    // ========================================================
    // Find shop/channel
    // ========================================================

    const channelDoc =
      await db
        .collection(
          'shopChannels'
        )
        .doc(
          incomingPhoneNumberId
        )
        .get();

    if (!channelDoc.exists) {
      console.log(
        `No shop registered for phone_number_id ${incomingPhoneNumberId}`
      );

      return res.sendStatus(200);
    }

    const channel = {
      ...channelDoc.data(),

      phoneNumberId:
        incomingPhoneNumberId,
    };

    // ========================================================
    // Process every message
    // ========================================================
    // Meta can deliver multiple messages in one request.
    // Process them sequentially so none are ignored.
    // ========================================================

    for (
      const message of messages
    ) {
      try {
        await processIncomingWhatsAppMessage(
          message,
          channel
        );
      } catch (messageError) {
        console.error(
          `Unexpected error while processing message ${
            message?.id || '(no-id)'
          }:`,
          messageError
        );
      }
    }

    return res.sendStatus(200);
  } catch (error) {
    console.error(
      'Webhook request error:',
      error
    );

    // Always acknowledge Meta webhook.
    return res.sendStatus(200);
  }
});

// ============================================================
// Broadcast listener - per shop
// ============================================================

db.collection('broadcasts')
  .where(
    'status',
    '==',
    'pending'
  )
  .onSnapshot(
    async (snapshot) => {
      for (
        const change of snapshot.docChanges()
      ) {
        if (
          change.type === 'added'
        ) {
          try {
            const broadcast =
              change.doc.data();

            const broadcastId =
              change.doc.id;

            const channelsSnapshot =
              await db
                .collection(
                  'shopChannels'
                )
                .where(
                  'ownerId',
                  '==',
                  broadcast.ownerId
                )
                .get();

            if (
              channelsSnapshot.empty
            ) {
              continue;
            }

            const channel =
              channelsSnapshot
                .docs[0]
                .data();

            const targetPhones =
              Array.isArray(
                broadcast.targetPhones
              )
                ? broadcast.targetPhones
                : [];

            console.log(
              `Processing broadcast for shop ${broadcast.ownerId} to ${targetPhones.length} customers...`
            );

            for (
              const phone of targetPhones
            ) {
              await sendWhatsAppMessage(
                phone,
                broadcast.message,
                channel.whatsappToken,
                channelsSnapshot
                  .docs[0]
                  .id
              );
            }

            await db
              .collection(
                'broadcasts'
              )
              .doc(
                broadcastId
              )
              .update({
                status: 'sent',
              });

            console.log(
              `Broadcast ${broadcastId} sent successfully.`
            );
          } catch (broadcastError) {
            console.error(
              'Broadcast processing error:',
              broadcastError
            );
          }
        }
      }
    },
    (error) => {
      console.error(
        'Broadcast listener error:',
        error
      );
    }
  );

// ============================================================
// Health check
// ============================================================

app.get('/', (req, res) => {
  res.status(200).json({
    success: true,
    service: 'Dukandesk WhatsApp backend',
    status: 'running',
  });
});

// ============================================================
// Start server
// ============================================================

const PORT =
  process.env.PORT || 5001;

app.listen(
  PORT,
  '0.0.0.0',
  () => {
    console.log(
      `Webhook listening on port ${PORT}`
    );
  }
);