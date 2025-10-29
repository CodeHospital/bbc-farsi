# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed
- Replaced OpenAI API with Ollama AI for local LLM inference
- Updated `update.rb` to use `ollama-ai` gem instead of `ruby-openai`
- Changed environment variable from `OPENAI_API_KEY` to `OLLAMA_URL` and `OLLAMA_MODEL`
- Updated API client initialization to use Ollama.new with local server address
- Modified chat completion call to use Ollama's chat method with compatible parameters
- Updated `.env.example` to include Ollama configuration variables
- Updated `readme.md` to reflect Ollama AI usage and setup instructions
- Updated `Dockerfile` to install `ollama-ai` gem instead of `httparty`
- Removed `OPENAI_API_KEY` from required environment variables (now using local Ollama)

### Fixed
- Added OpenSSL configuration to resolve "unable to get certificate CRL" SSL errors on macOS
- Configured certificate store to disable CRL checking for News API connections
