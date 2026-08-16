# Clean Code JavaScript – Full examples

Source: [clean-code-javascript](https://github.com/ryanmcdermott/clean-code-javascript). Good/bad pairs by topic.

---

## DIP – Dependency Injection

**Good:** Inject `requester`; easy to substitute (e.g. WebSockets).

```javascript
class InventoryTracker {
  constructor(items, requester) {
    this.items = items;
    this.requester = requester;
  }
  requestItems() {
    this.items.forEach(item => this.requester.requestItem(item));
  }
}
class InventoryRequesterV1 {
  constructor() { this.REQ_METHODS = ["HTTP"]; }
  requestItem(item) { /* ... */ }
}
class InventoryRequesterV2 {
  constructor() { this.REQ_METHODS = ["WS"]; }
  requestItem(item) { /* ... */ }
}
const inventoryTracker = new InventoryTracker(["apples", "bananas"], new InventoryRequesterV2());
inventoryTracker.requestItems();
```

**Bad:** High-level module creates low-level dependency.

```javascript
class InventoryTracker {
  constructor(items) {
    this.items = items;
    this.requester = new InventoryRequester(); // BAD: tight coupling
  }
  requestItems() {
    this.items.forEach(item => this.requester.requestItem(item));
  }
}
```

---

## SRP

**Good:** Auth in `UserAuth`; settings in `UserSettings` using it.

```javascript
class UserAuth {
  constructor(user) { this.user = user; }
  verifyCredentials() { /* ... */ }
}
class UserSettings {
  constructor(user) {
    this.user = user;
    this.auth = new UserAuth(user);
  }
  changeSettings(settings) {
    if (this.auth.verifyCredentials()) { /* ... */ }
  }
}
```

**Bad:** One class does settings and auth.

```javascript
class UserSettings {
  constructor(user) { this.user = user; }
  changeSettings(settings) {
    if (this.verifyCredentials()) { /* ... */ }
  }
  verifyCredentials() { /* ... */ }
}
```

---

## OCP

**Good:** Adapters with common `request`; `HttpRequester` delegates.

```javascript
class AjaxAdapter extends Adapter {
  request(url) { /* return promise */ }
}
class NodeAdapter extends Adapter {
  request(url) { /* return promise */ }
}
class HttpRequester {
  constructor(adapter) { this.adapter = adapter; }
  fetch(url) {
    return this.adapter.request(url).then(response => { /* transform and return */ });
  }
}
```

**Bad:** Branch on adapter type inside `fetch`.

```javascript
fetch(url) {
  if (this.adapter.name === "ajaxAdapter") {
    return makeAjaxCall(url).then(/* ... */);
  } else if (this.adapter.name === "nodeAdapter") {
    return makeHttpCall(url).then(/* ... */);
  }
}
```

---

## LSP

**Good:** `Rectangle` and `Square` extend `Shape`; each has `getArea()`.

```javascript
class Shape {
  setColor(color) { /* ... */ }
  render(area) { /* ... */ }
}
class Rectangle extends Shape {
  constructor(width, height) { super(); this.width = width; this.height = height; }
  getArea() { return this.width * this.height; }
}
class Square extends Shape {
  constructor(length) { super(); this.length = length; }
  getArea() { return this.length * this.length; }
}
function renderLargeShapes(shapes) {
  shapes.forEach(shape => {
    const area = shape.getArea();
    shape.render(area);
  });
}
```

**Bad:** `Square extends Rectangle` and overrides setters → wrong area when used as rectangle.

```javascript
class Square extends Rectangle {
  setWidth(width) { this.width = width; this.height = width; }
  setHeight(height) { this.width = height; this.height = height; }
}
// renderLargeRectangles with setWidth(4); setHeight(5) gives 25 for Square instead of 20
```

---

## ISP

**Good:** Optional nested `options`; client passes only what it needs.

```javascript
class DOMTraverser {
  constructor(settings) {
    this.settings = settings;
    this.options = settings.options;
    this.setup();
  }
  setupOptions() {
    if (this.options.animationModule) { /* ... */ }
  }
}
const $ = new DOMTraverser({
  rootNode: document.getElementsByTagName("body"),
  options: { animationModule() {} }
});
```

**Bad:** Fat settings; client must pass unused options.

```javascript
const $ = new DOMTraverser({
  rootNode: document.getElementsByTagName("body"),
  animationModule() {} // Often not needed
});
```

---

## Default object properties

**Bad:** Manual defaults.

```javascript
function createMenu(config) {
  config.title = config.title || "Foo";
  config.body = config.body || "Bar";
  config.cancellable = config.cancellable !== undefined ? config.cancellable : true;
}
```

**Good:** `Object.assign` with defaults.

```javascript
function createMenu(config) {
  const finalConfig = Object.assign(
    { title: "Foo", body: "Bar", buttonText: "Baz", cancellable: true },
    config
  );
  return finalConfig;
}
```

---

## Function arguments

**Bad:** Many positional parameters.

```javascript
function createMenu(title, body, buttonText, cancellable) { /* ... */ }
createMenu("Foo", "Bar", "Baz", true);
```

**Good:** Object destructuring.

```javascript
function createMenu({ title, body, buttonText, cancellable }) { /* ... */ }
createMenu({ title: "Foo", body: "Bar", buttonText: "Baz", cancellable: true });
```

---

## Default parameters

**Bad:** `||` replaces all falsy values.

```javascript
function createMicrobrewery(name) {
  const breweryName = name || "Hipster Brew Co.";
}
```

**Good:** ES6 default (only when `undefined`).

```javascript
function createMicrobrewery(name = "Hipster Brew Co.") { /* ... */ }
```

---

## Single responsibility & abstraction

**Bad:** One function does lookup, filter, and email.

```javascript
function emailClients(clients) {
  clients.forEach(client => {
    const clientRecord = database.lookup(client);
    if (clientRecord.isActive()) email(client);
  });
}
```

**Good:** Separate filter and action.

```javascript
function emailActiveClients(clients) {
  clients.filter(isActiveClient).forEach(email);
}
function isActiveClient(client) {
  const clientRecord = database.lookup(client);
  return clientRecord.isActive();
}
```

**Bad:** Multiple levels of abstraction in one function.

```javascript
function parseBetterJSAlternative(code) {
  const statements = code.split(" ");
  const tokens = [];
  REGEXES.forEach(REGEX => { /* ... */ });
  const ast = [];
  tokens.forEach(token => { /* ... */ });
  ast.forEach(node => { /* parse... */ });
}
```

**Good:** One level; helpers do details.

```javascript
function parseBetterJSAlternative(code) {
  const tokens = tokenize(code);
  const syntaxTree = parse(tokens);
  syntaxTree.forEach(node => { /* parse... */ });
}
function tokenize(code) { /* ... */ return tokens; }
function parse(tokens) { /* ... */ return syntaxTree; }
```

---

## No flag parameters

**Bad:** Boolean flag.

```javascript
function createFile(name, temp) {
  if (temp) fs.create(`./temp/${name}`);
  else fs.create(name);
}
```

**Good:** Two functions.

```javascript
function createFile(name) { fs.create(name); }
function createTempFile(name) { createFile(`./temp/${name}`); }
```

---

## Pure functions & immutability

**Bad:** Mutate global or argument.

```javascript
let name = "Ryan McDermott";
function splitIntoFirstAndLastName() { name = name.split(" "); }
```

```javascript
const addItemToCart = (cart, item) => { cart.push({ item, date: Date.now() }); };
```

**Good:** Return new value.

```javascript
function splitIntoFirstAndLastName(name) { return name.split(" "); }
const name = "Ryan McDermott";
const newName = splitIntoFirstAndLastName(name);
```

```javascript
const addItemToCart = (cart, item) => {
  return [...cart, { item, date: Date.now() }];
};
```

---

## Async

**Bad:** Nested callbacks.

```javascript
get("url", (requestErr, response, body) => {
  if (requestErr) console.error(requestErr);
  else writeFile("article.html", body, writeErr => {
    if (writeErr) console.error(writeErr);
    else console.log("File written");
  });
});
```

**Good:** Promises then async/await.

```javascript
get("url")
  .then(body => writeFile("article.html", body))
  .then(() => console.log("File written"))
  .catch(err => console.error(err));
```

```javascript
async function getArticle() {
  try {
    const body = await get("url");
    await writeFile("article.html", body);
    console.log("File written");
  } catch (err) {
    console.error(err);
  }
}
```

**Error handling:** In catch, use `console.error`, notify user, or report to service—not only `console.log`.

---

## Testing

**Bad:** Multiple concepts in one test.

```javascript
it("handles date boundaries", () => {
  let date = new MomentJS("1/1/2015"); date.addDays(30); assert.equal("1/31/2015", date);
  date = new MomentJS("2/1/2016"); date.addDays(28); assert.equal("02/29/2016", date);
  date = new MomentJS("2/1/2015"); date.addDays(28); assert.equal("03/01/2015", date);
});
```

**Good:** One concept per test.

```javascript
it("handles 30-day months", () => { /* ... */ });
it("handles leap year", () => { /* ... */ });
it("handles non-leap year", () => { /* ... */ });
```

---

## ES6 classes & inheritance

**Good:** `class` / `extends` / `super`.

```javascript
class Animal {
  constructor(age) { this.age = age; }
  move() { /* ... */ }
}
class Mammal extends Animal {
  constructor(age, furColor) {
    super(age);
    this.furColor = furColor;
  }
  liveBirth() { /* ... */ }
}
class Human extends Mammal {
  constructor(age, furColor, languageSpoken) {
    super(age, furColor);
    this.languageSpoken = languageSpoken;
  }
  speak() { /* ... */ }
}
```

**Bad:** ES5 prototype boilerplate (constructor checks, `Object.create`, manual `.constructor`).

---

## Composition over inheritance

**Bad:** “Has-a” modeled as “is-a”.

```javascript
class EmployeeTaxData extends Employee {
  constructor(ssn, salary) { super(); this.ssn = ssn; this.salary = salary; }
}
```

**Good:** Composition.

```javascript
class EmployeeTaxData {
  constructor(ssn, salary) { this.ssn = ssn; this.salary = salary; }
}
class Employee {
  setTaxData(ssn, salary) {
    this.taxData = new EmployeeTaxData(ssn, salary);
  }
}
```

---

## Method chaining

**Good:** Setters return `this`.

```javascript
class Car {
  setMake(make) { this.make = make; return this; }
  setModel(model) { this.model = model; return this; }
  setColor(color) { this.color = color; return this; }
  save() { console.log(this.make, this.model, this.color); return this; }
}
const car = new Car("Ford", "F-150", "red").setColor("pink").save();
```

**Bad:** Setters don’t return `this` → no chaining.

---

## Getters/setters & privacy

**Bad:** Public `balance`.

```javascript
return { balance: 0 };
const account = makeBankAccount();
account.balance = 100;
```

**Good:** Getter/setter (or closure).

```javascript
function makeBankAccount() {
  let balance = 0;
  function getBalance() { return balance; }
  function setBalance(amount) { /* validate */ balance = amount; }
  return { getBalance, setBalance };
}
```

**Private members (closure):**

```javascript
function makeEmployee(name) {
  return {
    getName() { return name; }
  };
}
```

---

## Avoid type-checking; use polymorphism

**Bad:** `instanceof` or `typeof` branches.

```javascript
function travelToTexas(vehicle) {
  if (vehicle instanceof Bicycle) vehicle.pedal(/* ... */);
  else if (vehicle instanceof Car) vehicle.drive(/* ... */);
}
```

**Good:** Common interface.

```javascript
function travelToTexas(vehicle) {
  vehicle.move(this.currentLocation, new Location("texas"));
}
```

**Bad:** Switch on type inside one method.

```javascript
getCruisingAltitude() {
  switch (this.type) {
    case "777": return this.getMaxAltitude() - this.getPassengerCount();
    case "Air Force One": return this.getMaxAltitude();
    case "Cessna": return this.getMaxAltitude() - this.getFuelExpenditure();
  }
}
```

**Good:** Override in subclasses.

```javascript
class Boeing777 extends Airplane {
  getCruisingAltitude() { return this.getMaxAltitude() - this.getPassengerCount(); }
}
class AirForceOne extends Airplane {
  getCruisingAltitude() { return this.getMaxAltitude(); }
}
class Cessna extends Airplane {
  getCruisingAltitude() { return this.getMaxAltitude() - this.getFuelExpenditure(); }
}
```

---

## Naming

- **Meaningful:** `currentDate = moment().format("YYYY/MM/DD")` not `yyyymmdstr`.
- **No mental mapping:** `locations.forEach(location => ...)` not `l`.
- **Searchable constants:** `MILLISECONDS_PER_DAY` not `86400000`.
- **Consistent vocabulary:** One term per concept (e.g. always `getUser()`).
- **Consistent capitalization:** e.g. `DAYS_IN_WEEK`, `eraseDatabase()`, `class Animal`.
- **No redundant context:** In `Car`, use `make`, `model`, `color` not `carMake`, `carModel`, `carColor`.

---

## Conditionals

- **Positive:** `if (isDOMNodePresent(node))` not `if (!isDOMNodeNotPresent(node))`.
- **Encapsulate:** `if (shouldShowSpinner(fsm, listNode))` not raw `fsm.state === "fetching" && isEmpty(listNode)`.

---

## Comments & structure

- Comment only **complex or non-obvious** logic; remove journal comments and commented-out code.
- **No positional markers:** Avoid `//// Scope Model` blocks.
- **Structure by caller/callee:** Place calling function above called (e.g. `perfReview` above `getPeerReviews` and `lookupPeers`).

---

## Remove dead code; don’t extend Array.prototype

**Good:** No unused functions; use version control for history.

**Bad:** Extending `Array.prototype.diff`; use `class SuperArray extends Array { diff(...) {} }` instead.

---

## Duplicate code

**Bad:** `showDeveloperList` and `showManagerList` with repeated structure.

**Good:** One `showEmployeeList` with `switch (employee.type)` for type-specific fields (e.g. `portfolio` vs `githubLink`).

---

## Don’t over-optimize

**Bad:** Caching `list.length` in loop “for performance” when not needed.

**Good:** Normal `for (let i = 0; i < list.length; i++)` (or `forEach`); optimize only when measured.
