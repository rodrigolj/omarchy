echo "Install Telegram as a default web app"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-refresh-applications
fi
