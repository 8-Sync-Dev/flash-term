# Modern JavaScript Tutorial — Reference Examples

Extended code examples for vanilla JavaScript, DOM, Fetch, and browser APIs. Read when you need concrete patterns.

## Variables and Data Types

```javascript
let name = "John";
const age = 30;
let greeting = `Hello, ${name}! You are ${age} years old.`;
let str = "Hello, World!";
console.log(str.length, str.toUpperCase(), str.slice(0, 5));
let num = Number("123");
```

## Array Methods

```javascript
let arr = [1, 2, 3, 4, 5];
let doubled = arr.map(x => x * 2);
let evens = arr.filter(x => x % 2 === 0);
let sum = arr.reduce((acc, curr) => acc + curr, 0);
items.splice(1, 1);
let copy = arr.slice(1, 3);
let user = users.find(u => u.id === 2);
```

## Object Basics

```javascript
let user = { name: "John", age: 30 };
console.log(user.name, user["age"]);
user.email = "john@example.com";
delete user.isAdmin;
for (let key in user) console.log(`${key}: ${user[key]}`);
Object.keys(user); Object.values(user); Object.entries(user);
```

## Classes

```javascript
class User {
  constructor(name, age) { this.name = name; this.age = age; }
  sayHi() { return `Hi, I'm ${this.name}`; }
}
class Admin extends User {
  constructor(name, age, role) { super(name, age); this.role = role; }
  sayHi() { return `${super.sayHi()}. I'm an ${this.role}.`; }
}
```

## Promises and Async/Await

```javascript
function loadData(url) {
  return new Promise((resolve, reject) => {
    setTimeout(() => url.startsWith("https://") ? resolve({ data: "Success" }) : reject(new Error("Invalid URL")), 1000);
  });
}
loadData("https://api.example.com").then(r => console.log(r.data)).catch(e => console.error(e.message));
async function fetchUserData(userId) {
  try {
    let response = await loadData(`https://api.example.com/users/${userId}`);
    return response;
  } catch (error) { return null; }
}
let results = await Promise.all(promises);
```

## Fetch API

```javascript
let response = await fetch('https://api.github.com/users');
if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
let users = await response.json();

await fetch(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer token123' },
  body: JSON.stringify(userData)
});

const controller = new AbortController();
setTimeout(() => controller.abort(), timeout);
await fetch(url, { signal: controller.signal });
```

## DOM Manipulation

```javascript
let div = document.createElement('div');
div.className = 'alert';
div.innerHTML = '<strong>Hi!</strong>';
document.body.append(div);

let button = document.getElementById('myButton');
let items = document.querySelectorAll('.item');
button.textContent = 'Click Me';
button.classList.add('active');
button.setAttribute('data-id', '123');

function createUserCard(name, email) {
  let card = document.createElement('div');
  card.className = 'user-card';
  card.innerHTML = `<h3>${name}</h3><p>${email}</p><button class="btn-delete">Delete</button>`;
  card.querySelector('.btn-delete').addEventListener('click', () => card.remove());
  return card;
}
```

## Event Handling

```javascript
button.addEventListener('click', (e) => { console.log(e.target); });
form.addEventListener('submit', (e) => {
  e.preventDefault();
  let data = Object.fromEntries(new FormData(form));
  fetch('/api/submit', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
});
list.addEventListener('click', (e) => {
  if (e.target.tagName === 'BUTTON') e.target.closest('li').remove();
});
button.removeEventListener('click', handleClick);
```

## Local Storage

```javascript
localStorage.setItem('username', 'john_doe');
localStorage.setItem('user', JSON.stringify(user));
let username = localStorage.getItem('username');
let userObject = JSON.parse(localStorage.getItem('user'));
localStorage.removeItem('theme');
localStorage.clear();
sessionStorage.setItem('sessionId', '123');
```

## Regular Expressions

```javascript
let hasHello = /Hello/.test(str);
let matches = text.match(/\w+/g);
let newMessage = message.replace(/World/, "JavaScript");
let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
let dateMatch = dateStr.match(/(\d{4})-(\d{2})-(\d{2})/);
let discounted = prices.replace(/\$(\d+)/g, (match, price) => '$' + (parseInt(price) * 0.9));
```
