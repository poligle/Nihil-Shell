.pragma library

// What PAM, its modules and greetd say, by what it is: the name of its text in theme/i18n.nix, or
// "" for anything else. greetd gives PAM's own names for what went wrong ("authentication error:
// pam_acct_mgmt: ACCT_EXPIRED"); PAM and its modules, sentences, in English or in the greeter's
// language. The first that fits is the one: in Spanish, a locked account's tells of failed
// «inicios de sesión».
var kinds = [
    ["authLocked", /\blocked\b|\bunlock|bloquead|desbloque/i],
    ["authTooMany", /maxtries|maximum number of (re)?tries|too many|demasiados|reintentos/i],
    ["authAccountExpired", /acct_expired|account (has )?expired|cuenta.*caducad|caducad.*cuenta/i],
    ["authExpired", /new_authtok_reqd|authtok_expired|token.*(no longer valid|expired|no es válido|caducad)|password (has )?expired|change your password|contraseña.*caducad|caducad.*contraseña|cambi\w* (su |la )?contraseña/i],
    ["authSession", /session|sesión/i],
    ["authFailed", /auth_err|authentication failure|login incorrect|perm_denied|permission denied|user_unknown|(fallo|error) de autenticación/i]
];

function kind(text) {
    const words = String(text);
    for (let i = 0; i < kinds.length; i++) {
        if (kinds[i][1].test(words))
            return kinds[i][0];
    }
    return "";
}

// What PAM said went wrong in a try, kept for when greetd says it failed: an error that says what
// it was, not one that only says it failed, nor a notice.
function told(text, error, before) {
    const own = error ? kind(text) : "";
    return own !== "" && own !== "authFailed" ? own : before;
}

// What a failed try is shown as: greetd's own word, if it says more than that it failed; or else
// what PAM said in the try, as pam_faillock says the account is locked and greetd no more than
// AUTH_ERR; or else a failure.
function failure(text, before) {
    const own = kind(text);
    return own !== "" && own !== "authFailed" ? own : before !== "" ? before : "authFailed";
}
