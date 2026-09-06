// Parser for order messages - handles single and multiple items

const wordQuantities = {
  'dozen': 12,
  'half dozen': 6,
  'a dozen': 12,
  'couple': 2,
  'a couple': 2,
};

const conversationalStopWords = [
  /\bchahye\b/gi,
  /\bchahiye\b/gi,
  /\bchahiay\b/gi,
  /\bchahida\b/gi,
  /\bghall do\b/gi,
  /\bghallo\b/gi,
  /\bbhej do\b/gi,
  /\bbhejo\b/gi,
  /\bde do\b/gi,
  /\bden\b/gi,
  /\blao\b/gi,
  /\bplease\b/gi,
  /\bzaroorat hai\b/gi,
];

function cleanConversationalPhrases(text) {
  let cleaned = text;
  for (const pattern of conversationalStopWords) {
    cleaned = cleaned.replace(pattern, '');
  }
  return cleaned.replace(/\s+/g, ' ').trim();
}

function normalizeUnit(unit) {
  const map = {
    'kg': 'kg',
    'kilo': 'kg',
    'kilos': 'kg',
    'g': 'g',
    'gram': 'g',
    'grams': 'g',
    'ltr': 'ltr',
    'litre': 'ltr',
    'litres': 'ltr',
    'l': 'ltr',
    'dozen': 'dozen',
    'pcs': 'pcs',
    'pc': 'pcs',
    'pack': 'pack',
    'packs': 'pack',
    'box': 'box',
    'boxes': 'box',
  };
  return map[unit] || 'pcs';
}

function parseSingleItem(segment) {
  let cleaned = cleanConversationalPhrases(segment.toLowerCase().trim());
  if (!cleaned) return null;

  for (const [word, value] of Object.entries(wordQuantities)) {
    const wordPattern = new RegExp(`^${word}\\s+([a-z\\s]+)`, 'i');
    const wordMatch = cleaned.match(wordPattern);
    if (wordMatch) {
      return {
        quantity: value,
        unit: 'pcs',
        productName: wordMatch[1].trim(),
      };
    }
  }

  const unitPattern = /(\d+(?:\.\d+)?)\s*(kg|kilo|kilos|g|gram|grams|ltr|litre|litres|l|dozen|pcs|pc|pack|packs|box|boxes)?\s+([a-z\s]+)/i;
  const match = cleaned.match(unitPattern);

  if (match) {
    let quantity = parseFloat(match[1]);
    const rawUnit = match[2] || 'pcs';

    if (rawUnit === 'dozen') {
      quantity = quantity * 12;
    }

    return {
      quantity,
      unit: rawUnit === 'dozen' ? 'pcs' : normalizeUnit(rawUnit),
      productName: match[3].trim(),
    };
  }

  return null;
}

function parseOrderMessage(text) {
  const segments = text
    .split(/\band\b|\baur\b|\bor\b|\bte\b|,|&/i)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  const items = [];
  const failedSegments = [];

  for (const segment of segments) {
    const parsedItem = parseSingleItem(segment);
    if (parsedItem) {
      items.push(parsedItem);
    } else {
      failedSegments.push(segment);
    }
  }

  if (items.length === 0) {
    return {
      success: false,
      rawText: text,
    };
  }

  return {
    success: true,
    items,
    partialFailure: failedSegments.length > 0,
    failedSegments,
  };
}

module.exports = { parseOrderMessage };