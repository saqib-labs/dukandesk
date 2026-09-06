require('dotenv').config();
const { GoogleGenerativeAI } = require('@google/generative-ai');

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

async function parseWithLLM(text, productNames = [], maxRetries = 2) {
  const model = genAI.getGenerativeModel({
    model: 'gemini-1.5-flash',
    generationConfig: {
      responseMimeType: 'application/json',
    },
  });

  const prompt = `You are an order parser for a grocery shop (kirana store).
The shop sells these products: ${productNames.length > 0 ? productNames.join(', ') : 'General Grocery Items'}

Customer message: "${text}"

Tasks:
1. Extract the ordered items. Match product names to the closest product from the shop's catalog above. Strip out conversational words across languages (e.g. Punjabi: "chahida", "ghall do", "ghallo", Urdu: "chahye", "bhej do").
2. Detect the customer's language name in English (e.g. "English", "Punjabi", "Urdu", "Pashto", "Arabic", "Hindi"). If written in Latin/Roman script but contains Punjabi words ("chahida", "kilo", "aata", "tay", "sanu"), detect as "Punjabi".

Respond with ONLY valid JSON in this exact structure:
{
  "items": [
    { "quantity": 1, "unit": "kg|g|ltr|pcs|dozen|pack|box", "productName": "exact name from shop list" }
  ],
  "isOrder": true,
  "language": "detected language name"
}

If the message is not an order (e.g. greeting, chat, question), respond with:
{ "items": [], "isOrder": false, "language": "detected language name" }`;

  let result;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('LLM request timed out after 8 seconds')), 8000)
      );

      const generatePromise = model.generateContent(prompt);
      result = await Promise.race([generatePromise, timeoutPromise]);
      break;
    } catch (err) {
      console.error(`LLM parse attempt ${attempt} failed:`, err.message);
      if (err.message?.includes('429')) throw err;
      if (attempt === maxRetries) {
        return { items: [], isOrder: false, language: 'English' };
      }
      await new Promise((resolve) => setTimeout(resolve, 1000 * attempt));
    }
  }

  try {
    const responseText = result.response.text().trim();
    const cleaned = responseText.replace(/```json|```/g, '').trim();
    return JSON.parse(cleaned);
  } catch (error) {
    console.error('LLM JSON parsing error:', error.message);
    return { items: [], isOrder: false, language: 'English' };
  }
}

module.exports = { parseWithLLM };