uv venv

source ./.venv/bin/activate
export PATH=`pwd`/.venv/bin:$PATH

uv pip install mkdocs mkdocs-material mkdocs-git-revision-date-localized-plugin mkdocs-include-markdown-plugin mkdocs-rss-plugin
