require ["envelope", "fileinto", "imap4flags", "regex"];

# Discard spam higher than level 10
if header :contains "X-Spam-Level" "**********" {
  discard;
  stop;
}

# Trash messages with improperly formed message IDs
if not header :regex "message-id" ".*@.*" {
  discard;
  stop;
}

# File spam higher than level 5
if header :contains "X-Spam-Level" "*****" {
  fileinto "INBOX.Junk";
  setflag "\\Seen";
  stop;
}

# File infected messages
if header :contains "X-Virus-Status" "Infected" {
  fileinto "INBOX.Infected";
  stop;
}

keep;