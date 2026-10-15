# Markdown twin of each news story (/news/:slug.md) for LLM / reader tools.
Mime::Type.register "text/markdown", :md unless Mime::Type.lookup_by_extension(:md)
