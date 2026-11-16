#!/bin/bash
# Met a jour la copie de Zen Player (app.zeniptv.mobile) sur GitHub (release "zen" de manuchane/manutv).
#  - cherche sur APKPure une version plus recente que celle de GitHub (variante Fire TV : 32 bits, Android 7+)
#  - verifie que les 3 fichiers sont signes par la cle Google Play de Zen
#  - remplace zen-base.apk, zen-arm32.apk, zen-fr.apk et zen-version.txt
# ManuTV compare zen-version.txt a la version installee et propose la mise a jour sur la tuile.
# Options : DRY=1 (ne publie rien), DEPART=143 (fait comme si GitHub avait cette version).
set -e
REPO=manuchane/manutv
PKG=app.zeniptv.mobile
CERT=ab8f42d9864da59a8108e828a12c94949e8fd3420ac94459acb5bfc0fac494f0   # cle Google Play de Zen
STAMP=3257d599a49d2c961a471ca9843f59d341a405884583fc087df4237b733bbd6d  # tampon Google Play
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

if command -v gh >/dev/null 2>&1; then GH=gh; else GH="/c/Program Files/GitHub CLI/gh.exe"; fi
if [ -n "$ANDROID_HOME" ] && ls "$ANDROID_HOME"/build-tools/*/apksigner >/dev/null 2>&1; then
    BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1); SIGNER="$BT/apksigner"; AAPT="$BT/aapt2"
else
    BT=$(ls -d /c/Users/manuc/AppData/Local/Android/Sdk/build-tools/* | tail -1); SIGNER="$BT/apksigner.bat"; AAPT="$BT/aapt2.exe"
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"

# version actuellement sur GitHub
if [ -n "$DEPART" ]; then ACTU=$DEPART
else ACTU=$(curl -sfL "https://github.com/$REPO/releases/download/zen/zen-version.txt?t=$(date +%s)" | tr -dc 0-9); fi
[ -z "$ACTU" ] && ACTU=149
echo "== GitHub : Zen versionCode $ACTU"

# APKPure : les numeros sautent (143, 149...) -> on essaie les 25 suivants, on garde le plus haut
TROUVE=""
for vc in $(seq $((ACTU + 25)) -1 $((ACTU + 1))); do
    curl -sL -A "$UA" -H "Referer: https://apkpure.com/" -o z.bin \
        "https://d.apkpure.net/b/XAPK/$PKG?versionCode=$vc&nc=armeabi-v7a&sv=30" || continue
    if unzip -l z.bin 2>/dev/null | grep -q "config.armeabi_v7a.apk"; then TROUVE=$vc; break; fi
done
if [ -z "$TROUVE" ]; then echo "== Rien de nouveau"; exit 0; fi
echo "== Nouvelle version trouvee : $TROUVE"

mkdir f && unzip -q z.bin -d f
for n in $PKG config.armeabi_v7a config.fr; do
    [ -f "f/$n.apk" ] || { echo "!! $n.apk absent"; exit 1; }
    out=$("$SIGNER" verify --print-certs "f/$n.apk" 2>&1)
    echo "$out" | grep -q "Signer #1 certificate SHA-256 digest: $CERT" || { echo "!! $n : mauvaise signature"; exit 1; }
    echo "$out" | grep -q "Source Stamp Signer certificate SHA-256 digest: $STAMP" || { echo "!! $n : pas de tampon Google Play"; exit 1; }
done
BADGE=$("$AAPT" dump badging "f/$PKG.apk" 2>/dev/null)
VC=$(echo "$BADGE" | grep -o "versionCode='[0-9]*'" | tr -dc 0-9)
NOM=$(echo "$BADGE" | grep -o "versionName='[^']*'" | cut -d"'" -f2)
MIN=$(echo "$BADGE" | grep -o "minSdkVersion:'[0-9]*'" | tr -dc 0-9)
echo "== $NOM (code $VC), Android minimum SDK $MIN"
[ "$VC" = "$TROUVE" ] || { echo "!! numero inattendu"; exit 1; }
[ "$MIN" -le 28 ] || { echo "!! demande Android trop recent pour les Fire TV (SDK $MIN)"; exit 1; }
unzip -l f/config.armeabi_v7a.apk | grep -q "lib/armeabi-v7a/libflutter.so" || { echo "!! bibliotheques 32 bits absentes"; exit 1; }

cp "f/$PKG.apk" zen-base.apk; cp f/config.armeabi_v7a.apk zen-arm32.apk; cp f/config.fr.apk zen-fr.apk
echo "$VC" > zen-version.txt
if [ -n "$DRY" ]; then echo "== DRY : rien publie"; exit 0; fi
# les 3 morceaux d'abord, le numero en dernier (ManuTV ne propose la mise a jour qu'une fois tout en place)
"$GH" release upload zen -R $REPO zen-base.apk zen-arm32.apk zen-fr.apk --clobber
"$GH" release upload zen -R $REPO zen-version.txt --clobber
"$GH" release edit zen -R $REPO --title "Zen Player $NOM (pour Fire TV)" \
    --notes "Zen IPTV Player $NOM ($PKG, code $VC), APK officiels Google Play verifies (signature $CERT) : zen-base.apk + zen-arm32.apk + zen-fr.apk, installes ensemble par ManuTV. Mis a jour automatiquement par zen-maj.sh." >/dev/null
echo "== Publie : Zen $NOM"
