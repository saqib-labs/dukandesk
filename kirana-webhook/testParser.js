const { parseOrderMessage } = require('./orderParser');

const testMessages = [
  "2kg rice",
  "2kg rice and 1 dozen eggs",
  "1 ltr oil, 3 pcs sugar and dozen eggs",
  "5 bread",
  "just chatting, not an order",
  "2kg rice and blah blah nonsense",
];

testMessages.forEach((msg) => {
  console.log(`Input: "${msg}"`);
  console.log(JSON.stringify(parseOrderMessage(msg), null, 2));
  console.log('---');
});