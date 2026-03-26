curl -s https://registry.npmjs.org/@thehugeman/opencode-anthropic-auth-community/latest | \
  node -e "const j=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(j.dist.tarball)" | \
  xargs curl -sL | tar -xzO package/index.mjs | \
  sed 's/console\.anthropic\.com/platform.claude.com/g' \
  > ~/.config/opencode/plugins/anthropic-auth.mjs
