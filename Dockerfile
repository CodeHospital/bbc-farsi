FROM ruby:3.2-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache build-base sqlite-dev

# Copy application files
COPY update.rb .
COPY .env* ./

# Install required gems
RUN gem install news-api telegram-bot-ruby httparty sqlite3 dotenv

# Create empty database file and log file
RUN touch /app/articles.db /app/cron.log

# Setup cron
RUN apk add --no-cache dcron && \
    echo '10 * * * * cd /app && ruby update.rb >> /app/cron.log 2>&1' > /etc/crontabs/root

# Copy the startup script
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Set the startup script as the entry point
ENTRYPOINT ["/app/start.sh"]