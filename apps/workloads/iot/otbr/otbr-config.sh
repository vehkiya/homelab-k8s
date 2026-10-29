#!/command/with-contenv sh
# s6 longrun: brings the Thread network up from THREAD_DATASET and re-applies the
# runtime settings otbr-agent does not persist across RCP resets.
while true; do
  # CCA threshold -60 dBm: ambient 2.4 GHz energy on channel 15 (-65 dBm) exceeds
  # OpenThread's -75 dBm default, so transmissions would otherwise fail CCA.
  ot-ctl ccathreshold -60 >/dev/null 2>&1 || true

  STATE=$(ot-ctl state 2>/dev/null || true)
  case "$STATE" in
    *disabled*)
      echo "[otbr-config] Thread is disabled. Configuring dataset and starting..."
      ot-ctl dataset set active "$THREAD_DATASET" >/dev/null || true
      ot-ctl ifconfig up || true
      ot-ctl thread start || true
      sleep 5
      ;;
    *child*|*router*|*leader*)
      # INTENTIONAL: advertise the Thread prefix with HIGH preference so
      # matter-server prefers this OTBR over the Google Nest Hub and Aqara
      # Hub M3, which advertise the same prefix at MEDIUM.
      ot-ctl br rioprf high >/dev/null || true
      ot-ctl br routeprf high >/dev/null || true
      ot-ctl netdata register >/dev/null || true
      ;;
  esac
  sleep 15
done
