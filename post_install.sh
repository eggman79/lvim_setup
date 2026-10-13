lvim --headless "+TSInstall cmake" +qa
lvim --headless "+MasonInstall cmake-language-server" +qa
VENV=/root/.local/share/lvim/mason/packages/cmake-language-server/venv

"$VENV/bin/python" -m pip install 'pygls==1.3.1'
"$VENV/bin/python" -m pip check

"$VENV/bin/python" -c \
  "from pygls.server import LanguageServer; from cmake_language_server.server import main; print('Importy OK')"
