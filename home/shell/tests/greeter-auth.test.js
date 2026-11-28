const fs = require("fs");
const path = require("path");
const assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../../../greeter/Auth.js"), "utf8").replace(".pragma library", "");
const A = new Function(source + "\nreturn { kind, told, failure };")();

let passed = 0;
function test(name, body) { body(); passed++; console.log("ok", name); }

test("greetd's errors by PAM's names", () => {
    assert.strictEqual(A.kind("authentication error: pam_authenticate: AUTH_ERR"), "authFailed");
    assert.strictEqual(A.kind("authentication error: pam_authenticate: MAXTRIES"), "authTooMany");
    assert.strictEqual(A.kind("authentication error: pam_acct_mgmt: ACCT_EXPIRED"), "authAccountExpired");
    assert.strictEqual(A.kind("authentication error: pam_acct_mgmt: NEW_AUTHTOK_REQD"), "authExpired");
    assert.strictEqual(A.kind("authentication error: pam_acct_mgmt: AUTHTOK_EXPIRED"), "authExpired");
    assert.strictEqual(A.kind("authentication error: pam_acct_mgmt: PERM_DENIED"), "authFailed");
    assert.strictEqual(A.kind("session start failed: could not open session"), "authSession");
});

test("PAM's and its modules' sentences, in English", () => {
    assert.strictEqual(A.kind("authentication failure"), "authFailed");
    assert.strictEqual(A.kind("Login incorrect"), "authFailed");
    assert.strictEqual(A.kind("The account is locked due to 3 failed logins."), "authLocked");
    assert.strictEqual(A.kind("(2 minutes left to unlock)"), "authLocked");
    assert.strictEqual(A.kind("Account temporary locked (60 seconds left)"), "authLocked");
    assert.strictEqual(A.kind("Your account has expired; please contact your system administrator."), "authAccountExpired");
    assert.strictEqual(A.kind("User account has expired"), "authAccountExpired");
    assert.strictEqual(A.kind("You are required to change your password immediately (administrator enforced)."), "authExpired");
    assert.strictEqual(A.kind("Authentication token is no longer valid; new one required"), "authExpired");
    assert.strictEqual(A.kind("Have exhausted maximum number of retries for service"), "authTooMany");
});

test("and in Spanish", () => {
    assert.strictEqual(A.kind("La cuenta está bloqueada debido a 3 inicios de sesión fallidos."), "authLocked");
    assert.strictEqual(A.kind("Su cuenta ha caducado; póngase en contacto con el administrador del sistema"), "authAccountExpired");
    assert.strictEqual(A.kind("Debe cambiar su contraseña inmediatamente (impuesto por el administrador)."), "authExpired");
    assert.strictEqual(A.kind("Su contraseña ha caducado"), "authExpired");
    assert.strictEqual(A.kind("Se ha agotado el número máximo de reintentos para el servicio"), "authTooMany");
    assert.strictEqual(A.kind("Fallo de autenticación"), "authFailed");
});

test("anything else is nothing known", () => {
    assert.strictEqual(A.kind("Warning: your password will expire in 5 days"), "");
    assert.strictEqual(A.kind("Verification code: "), "");
    assert.strictEqual(A.kind("An unknown error occurred"), "");
    assert.strictEqual(A.kind(""), "");
});

test("what PAM said in a try is what the failure shows", () => {
    // pam_faillock says the account is locked, and greetd no more than that it failed.
    let told = "";
    told = A.told("The account is locked due to 3 failed logins.", true, told);
    told = A.told("(2 minutes left to unlock)", false, told);
    assert.strictEqual(told, "authLocked");
    assert.strictEqual(A.failure("authentication error: pam_authenticate: AUTH_ERR", told), "authLocked");
    // greetd's own word, when it says more, comes first.
    assert.strictEqual(A.failure("authentication error: pam_authenticate: MAXTRIES", told), "authTooMany");
    // Only errors that say what went wrong are kept.
    assert.strictEqual(A.told("authentication failure", true, ""), "");
    assert.strictEqual(A.told("Your account has expired", false, ""), "");
    assert.strictEqual(A.told("An unknown error occurred", true, "authLocked"), "authLocked");
    // With nothing said, a failure.
    assert.strictEqual(A.failure("authentication error: pam_authenticate: AUTH_ERR", ""), "authFailed");
    assert.strictEqual(A.failure("", ""), "authFailed");
});

console.log(passed, "passed");
