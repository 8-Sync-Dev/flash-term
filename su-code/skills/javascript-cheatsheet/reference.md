# JavaScript Cheatsheet – Full reference

Source: [javascript-cheatsheet](https://github.com/wilfredinni/javascript-cheatsheet). Snippets by topic.

---

## Setup

### Install pnpm (Linux/macOS)
```shell
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

### Install pnpm (Windows PowerShell)
```shell
iwr https://get.pnpm.io/install.ps1 -useb | iex
```

### Clone and install
```shell
git clone https://github.com/wilfredinni/javascript-cheatsheet.git
cd javascript-cheatsheet
pnpm install
```

### Branch, commit, push
```shell
git branch fix_bug
git checkout fix_bug
git add .
git commit -m 'succinct explanation of what changed'
git push origin fix_bug
```

---

## Control flow

### Switch
```javascript
let fruit = 'apple';
switch (fruit) {
  case 'banana':
    console.log('I am a banana');
    break;
  case 'apple':
    console.log('I am an apple');
    break;
  default:
    console.log('I am not a banana or an apple');
}
```

### Ternary
```javascript
let a = 10;
let result = a > 5 ? 'a is greater than 5' : 'a is not greater than 5';
```

### For / do-while / while
```javascript
for (let i = 0; i < 5; i++) { console.log(i); }
let i = 0;
do { console.log(i); i++; } while (i < 5);
while (i < 5) { console.log(i); i++; }
```

### For vs map
```javascript
let arrFor = [1, 2, 3, 4, 5];
for (let i = 0; i < arrFor.length; i++) arrFor[i] = arrFor[i] * 2;

let arrMap = [1, 2, 3, 4, 5];
let doubled = arrMap.map(num => num * 2); // arrMap unchanged
```

---

## Arrays

### Declaration, length, access
```javascript
let fruits = ['apple', 'banana', 'cherry'];
console.log(fruits.length);
console.log(fruits[0]);
fruits[1] = 'blueberry';
```

### push, unshift, pop, shift, splice, slice
```javascript
fruits.push('orange');
fruits.unshift('apple', 'pineapple');
let last = fruits.pop();
let first = fruits.shift();
let removed = fruits.splice(2, 2);
let citrus = fruits.slice(2, 4);
let rest = fruits.slice(2);
```

### map, filter, reduce, flatMap, flat
```javascript
let roots = [1, 4, 9, 16].map(Math.sqrt);
let filtered = numbers.filter(x => x > 13);
let sum = numbers.reduce((acc, cur) => acc + cur, 0);
let flat = arr.flatMap(x => x.split(' '));
let flatArray = nested.flat(2);
```

### find, findIndex, indexOf, includes
```javascript
let found = numbers.find(x => x > 13);
let idx = numbers.findIndex(x => x > 13);
let i = fruits.indexOf('banana');
let has = fruits.includes('banana');
```

### entries, keys, values, join, reverse, sort, fill
```javascript
for (let [index, value] of array.entries()) { }
for (let key of array.keys()) { }
for (let value of array.values()) { }
let str = fruits.join(' - ');
fruits.reverse();
numbers.sort((a, b) => a - b);
numbers.fill(0, 1, 3);
```

### Array.from, spread, concat
```javascript
let arr = Array.from('hello');
let more = [...fruits, 'date'];
let all = [...fruits1, ...fruits2];
let merged = fruits1.concat(fruits2, fruits3);
```

---

## Objects

### Literal, dot/bracket, methods
```javascript
let car = {
  maker: "Toyota",
  model: "Camry",
  year: 2020,
  startEngine: function() { return "Engine started"; }
};
console.log(car.maker);
console.log(car['model']);
obj.key3 = 'value3';
obj['key3'] = 'value3';
```

### Property checks, iteration
```javascript
'key1' in obj;
obj.hasOwnProperty('key1');
for (let key in obj) {
  if (obj.hasOwnProperty(key)) console.log(key + ': ' + obj[key]);
}
```

---

## Functions

### Declaration, expression, arrow
```javascript
function add(a, b) { return a + b; }
let addRegular = function(a, b) { return a + b; };
let addArrow = (a, b) => a + b;
let square = x => x * x;
```

### this: arrow vs regular
```javascript
let obj2 = {
  value: 'a',
  createArrowFunction: function() {
    return () => console.log(this.value); // lexical this
  }
};
obj2.createArrowFunction()(); // 'a'
```

### Hoisting
```javascript
greet(); // works for function declaration
function greet() { console.log("Hello"); }
// greet(); // error for expression before assignment
let greet = function() { };
```

---

## Strings

### slice, split, replace, trim, indexOf, includes, charAt
```javascript
let sliced = str.slice(7, 12);
let parts = str.split(", ");
let newStr = str.replace("World", "Universe");
let trimmed = str.trim();
let idx = str.indexOf("World");
let has = str.includes("World");
let char = str.charAt(7);
```

### Template literals
```javascript
let greeting = `Hello, my name is ${name} and I am ${age} years old.`;
```

---

## Set

### Create, add, delete, has, clear, size, iterate
```javascript
let set1 = new Set();
let set2 = new Set([1, 2, 3, 4, 5]);
set.add(1);
set.delete(2);
set.has(3);
set.clear();
console.log(set.size);
for (let value of set) { }
set.forEach(v => console.log(v));
```

### Union, intersection, difference
```javascript
let union = new Set([...setA, ...setB]);
let intersection = new Set([...setA].filter(x => setB.has(x)));
let difference = new Set([...setA].filter(x => !setB.has(x)));
```

---

## Map

### Create, set, get, has, delete, clear, size
```javascript
const map = new Map();
const map = new Map([['id', 1], ['name', 'Alice']]);
map.set('age', 50);
map.get('age');
map.has('id');
map.delete('age');
map.clear();
```

### Iterate
```javascript
for (let [key, value] of map.entries()) { }
for (const key of map.keys()) { }
for (const value of map.values()) { }
for (const [key, value] of map) { }
```

---

## Regular expressions

### Anchors, quantifiers, groups, lookahead
```javascript
/^abc/.test('abcdef');
/def$/.test('abcdef');
/a*/.test('aaaabc');
/a+/.test('aaaabc');
/(abc)/.test('abcdef');
/(?:abc)/.test('abcdef');
/abc(?=def)/.test('abcdef');
/abc(?!def)/.test('abcghi');
```

### Character sets, digit, word, whitespace
```javascript
/[abc]/.test('defabc');
/[^abc]/.test('defabc');
/\d/.test('abc123');
/\w/.test('abc');
/\s/.test('abc def');
```

---

## Error handling

### try/catch/finally
```javascript
try {
  // code that may throw
} catch (error) {
  console.log(error.message);
} finally {
  // always runs
}
```

### Async with async/await
```javascript
async function performAsyncOperations() {
  try {
    const result = await doSomething();
    await doAnotherThing(result);
  } catch (error) {
    console.error('An error occurred:', error);
  }
}
```

### Custom error
```javascript
class DivisionByZeroError extends Error {
  constructor() {
    super("Division by zero is not allowed");
    this.name = "DivisionByZeroError";
  }
}
throw new DivisionByZeroError();
```

---

## Debugging

### console.time, group, table, assert, trace
```javascript
console.time('Array processing');
// ... code ...
console.timeEnd('Array processing');

console.group('Processing array');
console.log('Array has', array.length, 'elements');
console.groupEnd();

console.table(people);

console.assert(1 === 2, '1 is not equal to 2');

function thirdFunction() { console.trace(); }
```

### debugger
```javascript
debugger; // pauses when devtools open
```

---

## Node.js fs (promises)

### Read/write/append file
```javascript
const fs = require('fs').promises;
const data = await fs.readFile(filePath, 'utf8');
await fs.writeFile(filePath, content);
await fs.appendFile(filePath, content);
await fs.unlink(filePath);
await fs.rename(oldPath, newPath);
```

### Directory
```javascript
await fs.mkdir(dirPath, { recursive: true });
const files = await fs.readdir(dirPath);
await fs.rmdir(dirPath); // empty only
```

### Check exists
```javascript
async function checkExists(path) {
  try {
    await fs.access(path);
    console.log('Exists');
  } catch {
    console.log('Does not exist');
  }
}
```

### Watch file
```javascript
const fs = require('fs');
fs.watch('example.txt', (eventType, filename) => {
  console.log(`${eventType}: ${filename}`);
});
```

---

## Testing (Jest)

```javascript
const sum = require('./sum');

test('adds 1 + 2 to equal 3', () => {
  expect(sum(1, 2)).toBe(3);
});
```

---

## Basics

### let, var, const
```javascript
let age = 25;
var name = "John";
const pi = 3.14159;
```

### Operators
```javascript
5 ** 2;        // 25
x += 10;
num++;
5 === 5;       // true
5 === '5';     // false
```

### console.log
```javascript
console.log("Hello, World!");
console.log(x);
console.log('Hello, %s', name);
console.log(x, y);
```
