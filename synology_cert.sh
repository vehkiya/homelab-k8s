#!/usr/bin/env sh
# Run this inside Synology's shell as certadmin

# --- Configuration ---
ACME_INSTALL_DIR="/usr/local/share/acme.sh"
ACME_DATA_DIR="${ACME_INSTALL_DIR}/data" # Persistent directory for acme.sh data
SYNO_Username="$(whoami)"

if [ -z "${SYNO_PORT}" ]; then
  echo "⚠️ SYNO_PORT is not set. If you use a non-standard port for DSM, please set this environment variable."
fi

# --- Helper Functions ---
prompt_if_empty() {
  local var_name="$1"
  local current_val_check # Temporary variable for the check

  # Check if the variable is set using indirect expansion via eval.
  eval "current_val_check=\$$var_name"

  if [ -z "$current_val_check" ]; then
    # Use printf for prompting, it's safer with potentially special characters.
    printf "🤔 '%s' is not set. Please enter value: " "$var_name"
    read -r user_input # Use -r to prevent backslash interpretation by read

    eval "$var_name=\"\$user_input\""
    
    # Export the variable. This uses the value of var_name as the variable name to export.
    export "$var_name"
  else
    # Use printf for consistency and safety.
    printf "👍 '%s' is already set to: \"%s\"\n" "$var_name" "$current_val_check"
  fi
}

# --- Main Script ---

echo "🚀 Starting ACME.sh certificate script for Synology DSM..."

# Synology DSM Credentials for deployment
prompt_if_empty "SYNO_Username" # DSM Username (use an admin account)

# 1. Install acme.sh if not present
if [ ! -f "${ACME_INSTALL_DIR}/acme.sh" ]; then
  echo "ℹ️ acme.sh not found at ${ACME_INSTALL_DIR}. Installing now..."
  wget -O /tmp/acme.sh.zip https://github.com/acmesh-official/acme.sh/archive/master.zip
  if [ $? -ne 0 ]; then
    echo "❌ Error downloading acme.sh. Please check your internet connection or the URL."
    exit 1
  fi
  echo "📦 Unzipping acme.sh..."
  sudo 7z x -o/usr/local/share /tmp/acme.sh.zip
  if [ $? -ne 0 ]; then
    echo "❌ Error unzipping acme.sh. Make sure '7z' (p7zip) is installed."
    # You might need to install p7zip via Synology's Package Center or opkg if available
    # e.g., sudo opkg install p7zip
    exit 1
  fi
  sudo mv /usr/local/share/acme.sh-master/ "${ACME_INSTALL_DIR}"
  sudo chown -R ${SYNO_Username}:users "${ACME_INSTALL_DIR}" # Assuming 'certadmin' user and 'users' group
  echo "✅ acme.sh installed successfully to ${ACME_INSTALL_DIR}"
else
  echo "✅ acme.sh is already installed at ${ACME_INSTALL_DIR}."
fi

# Create data directory if it doesn't exist
sudo mkdir -p "${ACME_DATA_DIR}"
sudo chown -R ${SYNO_Username}:users "${ACME_DATA_DIR}" # Ensure certadmin can write here

# 2. Set and Prompt for Environment Variables
echo "🔑 Checking environment variables..."
# Cloudflare Credentials
prompt_if_empty "CF_Token"     # Cloudflare API Token
prompt_if_empty "CF_Email"     # Cloudflare Account Email (optional if using CF_Key and CF_Email for global API key)
prompt_if_empty "SYNO_Password" # DSM Password
export SYNO_Create=1            # Create certificate in DSM if it doesn't exist
# Domain for the certificate
prompt_if_empty "DOMAIN"       # Your domain, e.g., example.com or sub.example.com
prompt_if_empty "ACME_EMAIL"

echo "⚙️ Using the following configuration:"
echo "   - Domain: $DOMAIN"
echo "   - Cloudflare Email: $CF_Email"
echo "   - Synology User: $SYNO_Username"
echo "   - ACME Home Dir: $ACME_DATA_DIR"

# 3. Issue Certificate
echo "📜 Requesting certificate for '$DOMAIN' using DNS-01 challenge with Cloudflare..."
# Ensure the acme.sh script is executable
sudo chmod +x "${ACME_INSTALL_DIR}/acme.sh"

# Run acme.sh as the certadmin user if possible, or ensure current user has rights to ACME_DATA_DIR
# If running as root, it's fine. If running as another user, 'sudo -u certadmin ...' might be needed
# or ensure current user owns/can write to ACME_DATA_DIR.
# For simplicity, if you are root, this will work. If you are certadmin, this will work.
"${ACME_INSTALL_DIR}/acme.sh" --issue \
    -d "$DOMAIN" \
    --dns dns_cf \
    --home "${ACME_DATA_DIR}" \
    --log "${ACME_DATA_DIR}/acme.sh.log"\
    --accountemail "${ACME_EMAIL}"

if [ $? -ne 0 ]; then
  echo "❌ Error issuing certificate. Check logs at ${ACME_DATA_DIR}/acme.sh.log"
  exit 1
fi
echo "✅ Certificate issued successfully for $DOMAIN!"

# 4. Deploy Certificate to Synology DSM
echo "🛡️ Deploying certificate for $DOMAIN to Synology DSM..."
"${ACME_INSTALL_DIR}/acme.sh" \
    -d "$DOMAIN" \
    --deploy --deploy-hook synology_dsm \
    --home "${ACME_DATA_DIR}"

if [ $? -ne 0 ]; then
  echo "❌ Error deploying certificate to Synology DSM. Check logs."
  exit 1
fi
echo "🎉 Certificate for $DOMAIN deployed successfully to Synology DSM!"
echo "💡 You might need to manually assign the new certificate to services (e.g., Web Station, Synology Drive) via DSM Control Panel > Security > Certificate."

# --- End of Script ---