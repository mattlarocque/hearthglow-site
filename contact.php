<?php
/**
 * Hearthglow — Quote Request Handler
 *
 * Receives the quote form POST, validates it, sends an email to Matt,
 * and returns a JSON response to the page's JavaScript.
 *
 * No third-party dependencies. Runs entirely on CanSpace's PHP server.
 * PHP 8.x required (included on all CanSpace plans).
 */

// ── Config ────────────────────────────────────────────────────────────────────
define('DEST_EMAIL',    'matt@hearthglow.ca');
define('SENDER_EMAIL',  'noreply@hearthglow.ca');
define('SENDER_NAME',   'Hearthglow Website');
define('SITE_URL',      'https://hearthglow.ca');
define('RATE_LIMIT',    3);   // max submissions per IP per hour
define('RATE_FILE',     sys_get_temp_dir() . '/hg_ratelimit.json');

// ── Security headers ──────────────────────────────────────────────────────────
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');

// Only accept POST from our own origin
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'Method not allowed']);
    exit;
}
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (!empty($origin) && !in_array($origin, [SITE_URL, 'https://www.' . parse_url(SITE_URL, PHP_URL_HOST)], true)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Forbidden']);
    exit;
}

// ── Accept JSON body (landing form posts application/json) ─────────────────────
// The landing form submits the intake directly to the API (/api/v1/quote-intake)
// and then fires a best-effort, fire-and-forget notification POST here so Matt
// still gets pinged. We normalise the camelCase JSON into the snake_case fields
// the rest of this handler already expects.
$raw_input = file_get_contents('php://input');
if (!empty($raw_input)) {
    $json = json_decode($raw_input, true);
    if (is_array($json)) {
        $_POST = array_merge($_POST, [
            'first_name'     => $json['firstName']     ?? $json['first_name']     ?? '',
            'last_name'      => $json['lastName']      ?? $json['last_name']      ?? '',
            'email'          => $json['email']         ?? '',
            'phone'          => $json['phone']         ?? '',
            'address'        => $json['address']       ?? '',
            'tier_interest'  => $json['tierInterest']  ?? $json['tier_interest']  ?? '',
            'install_window' => $json['installWindow'] ?? $json['install_window'] ?? '',
            'notes'          => $json['notes']         ?? '',
        ]);
    }
}

// ── Rate limiting ─────────────────────────────────────────────────────────────
function check_rate_limit(string $ip): bool {
    $data = [];
    if (file_exists(RATE_FILE)) {
        $data = json_decode(file_get_contents(RATE_FILE), true) ?: [];
    }
    $now = time();
    $window = $now - 3600;
    $data = array_filter($data, fn($t) => $t > $window);
    $ip_hits = array_filter($data, fn($t, $k) => str_starts_with($k, $ip . '_'), ARRAY_FILTER_USE_BOTH);
    if (count($ip_hits) >= RATE_LIMIT) return false;
    $data[$ip . '_' . $now] = $now;
    file_put_contents(RATE_FILE, json_encode($data), LOCK_EX);
    return true;
}
$client_ip = $_SERVER['HTTP_CF_CONNECTING_IP']  // Cloudflare real IP
           ?? $_SERVER['HTTP_X_FORWARDED_FOR']
           ?? $_SERVER['REMOTE_ADDR']
           ?? 'unknown';

if (!check_rate_limit($client_ip)) {
    http_response_code(429);
    echo json_encode(['ok' => false, 'error' => 'Too many requests — please try again in an hour.']);
    exit;
}

// ── Input sanitization helpers ────────────────────────────────────────────────
function clean(string $val, int $maxlen = 300): string {
    return mb_substr(trim(strip_tags($val)), 0, $maxlen);
}
function clean_email(string $val): string {
    return filter_var(trim($val), FILTER_SANITIZE_EMAIL);
}

// ── Honeypot check (spam bots fill hidden fields) ─────────────────────────────
if (!empty($_POST['_gotcha'])) {
    // Silently succeed so bots think it worked
    echo json_encode(['ok' => true]);
    exit;
}

// ── Read and validate fields ──────────────────────────────────────────────────
$first_name    = clean($_POST['first_name']    ?? '');
$last_name     = clean($_POST['last_name']     ?? '');
$email         = clean_email($_POST['email']   ?? '');
$phone         = clean($_POST['phone']         ?? '', 30);
$address       = clean($_POST['address']       ?? '');
$tier_interest = clean($_POST['tier_interest'] ?? '', 50);
$install_window = clean($_POST['install_window'] ?? '', 50);
$notes         = clean($_POST['notes']         ?? '', 2000);

$errors = [];
if (empty($first_name)) $errors[] = 'First name is required.';
if (empty($last_name))  $errors[] = 'Last name is required.';
if (empty($email) || !filter_var($email, FILTER_VALIDATE_EMAIL)) $errors[] = 'A valid email address is required.';
if (empty($address))    $errors[] = 'Property address is required.';

if (!empty($errors)) {
    http_response_code(422);
    echo json_encode(['ok' => false, 'error' => implode(' ', $errors)]);
    exit;
}

// ── Map tier/window values to human-readable labels ───────────────────────────
$tier_labels = [
    'home'   => 'Home (labour only — client supplies lights)',
    'bright' => 'Bright (full supply + install)',
    'merry'  => 'Merry (Bright + aerial drone reel)',
    'unsure' => 'Not sure — help me choose',
    ''       => 'Not specified',
];
$window_labels = [
    'oct-early' => 'Early October (Oct 1–15)',
    'oct-late'  => 'Late October (Oct 16–31)',
    'nov-early' => 'Early November (Nov 1–15)',
    'nov-late'  => 'Late November (Nov 16–30)',
    'flexible'  => 'Flexible — Matthew\'s call',
    ''          => 'Not specified',
];
$tier_label   = $tier_labels[$tier_interest]    ?? $tier_interest;
$window_label = $window_labels[$install_window] ?? $install_window;

// ── Build email ───────────────────────────────────────────────────────────────
$full_name = "{$first_name} {$last_name}";
$submitted = date('D, M j Y \a\t g:ia T');

$subject = "New Quote Request — {$full_name} ({$tier_label})";

$body_html = <<<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; background: #f4f4f4; margin: 0; padding: 20px; }
    .card { background: #fff; border-radius: 8px; padding: 32px; max-width: 600px; margin: 0 auto; border-top: 4px solid #C9A84C; }
    h2 { color: #1B3A5C; margin: 0 0 4px; }
    .subtitle { color: #888; font-size: 14px; margin: 0 0 24px; }
    .row { display: flex; margin-bottom: 12px; }
    .label { color: #555; font-size: 13px; font-weight: bold; min-width: 160px; }
    .value { color: #222; font-size: 14px; }
    .notes-block { background: #f9f6f0; border-left: 3px solid #C9A84C; padding: 12px 16px; border-radius: 4px; margin-top: 16px; color: #333; font-size: 14px; }
    .footer { margin-top: 24px; font-size: 12px; color: #aaa; text-align: center; }
    .action { text-align: center; margin: 24px 0; }
    .btn { background: #C9A84C; color: #1B3A5C; padding: 12px 28px; border-radius: 50px; text-decoration: none; font-weight: bold; font-size: 14px; }
  </style>
</head>
<body>
<div class="card">
  <h2>New Quote Request</h2>
  <p class="subtitle">Submitted {$submitted} via hearthglow.ca</p>

  <div class="row"><span class="label">Name</span><span class="value">{$full_name}</span></div>
  <div class="row"><span class="label">Email</span><span class="value"><a href="mailto:{$email}">{$email}</a></span></div>
  <div class="row"><span class="label">Phone</span><span class="value">{$phone}</span></div>
  <div class="row"><span class="label">Property address</span><span class="value">{$address}</span></div>
  <div class="row"><span class="label">Tier interest</span><span class="value">{$tier_label}</span></div>
  <div class="row"><span class="label">Preferred window</span><span class="value">{$window_label}</span></div>

  <div class="notes-block"><strong>Additional notes:</strong><br>{$notes}</div>

  <div class="action">
    <a href="mailto:{$email}?subject=Re: Your Hearthglow quote request&body=Hi {$first_name}," class="btn">Reply to {$first_name}</a>
  </div>

  <p class="footer">Hearthglow · hearthglow.ca · matt@hearthglow.ca</p>
</div>
</body>
</html>
HTML;

$body_text = "New Quote Request — hearthglow.ca\n"
    . "Submitted: {$submitted}\n\n"
    . "Name:              {$full_name}\n"
    . "Email:             {$email}\n"
    . "Phone:             {$phone}\n"
    . "Property address:  {$address}\n"
    . "Tier interest:     {$tier_label}\n"
    . "Preferred window:  {$window_label}\n\n"
    . "Additional notes:\n{$notes}\n\n"
    . "---\nReply to: {$email}\n";

// ── Send via PHP mail() ───────────────────────────────────────────────────────
$boundary = md5(uniqid((string)rand(), true));
$headers  = implode("\r\n", [
    "From: {$full_name} via Hearthglow <" . SENDER_EMAIL . ">",
    "Reply-To: {$full_name} <{$email}>",
    "MIME-Version: 1.0",
    "Content-Type: multipart/alternative; boundary=\"{$boundary}\"",
    "X-Mailer: HearthglowContactForm/1.0",
]);

$message = "--{$boundary}\r\n"
    . "Content-Type: text/plain; charset=utf-8\r\n"
    . "Content-Transfer-Encoding: 8bit\r\n\r\n"
    . $body_text . "\r\n"
    . "--{$boundary}\r\n"
    . "Content-Type: text/html; charset=utf-8\r\n"
    . "Content-Transfer-Encoding: 8bit\r\n\r\n"
    . $body_html . "\r\n"
    . "--{$boundary}--";

$sent = mail(DEST_EMAIL, $subject, $message, $headers);

// ── Send confirmation to submitter ────────────────────────────────────────────
if ($sent) {
    $confirm_subject = "Your Hearthglow quote request — we'll be in touch";
    $confirm_body    = "Hi {$first_name},\r\n\r\n"
        . "Thanks for reaching out to Hearthglow! I've received your quote request "
        . "and will get back to you within 24 hours with a custom quote for your home.\r\n\r\n"
        . "What you submitted:\r\n"
        . "  Property: {$address}\r\n"
        . "  Service interest: {$tier_label}\r\n"
        . "  Preferred window: {$window_label}\r\n\r\n"
        . "Looking forward to it.\r\n\r\n"
        . "Matthew\r\nHearthglow\r\nmatt@hearthglow.ca\r\n";
    $confirm_headers = "From: Matthew at Hearthglow <" . SENDER_EMAIL . ">\r\n"
        . "Content-Type: text/plain; charset=utf-8";
    mail($email, $confirm_subject, $confirm_body, $confirm_headers);
}

// ── Log submission ─────────────────────────────────────────────────────────────
$log_entry = json_encode([
    'ts'      => $submitted,
    'name'    => $full_name,
    'email'   => $email,
    'address' => $address,
    'tier'    => $tier_label,
    'window'  => $window_label,
    'ip'      => substr(md5($client_ip), 0, 8), // hashed for privacy
    'sent'    => $sent,
]) . "\n";
file_put_contents(
    __DIR__ . '/logs/quotes.log',
    $log_entry,
    FILE_APPEND | LOCK_EX
);

// ── Respond ───────────────────────────────────────────────────────────────────
if ($sent) {
    echo json_encode(['ok' => true]);
} else {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Mail delivery failed — please email matt@hearthglow.ca directly.']);
}
