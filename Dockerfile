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
    echo '*/10 * * * * cd /app && ruby update.rb >> /app/cron.log 2>&1' > /etc/crontabs/root

# Create a startup script that runs both crond and the initial update
RUN echo '#!/bin/sh' > /app/start.sh && \
    echo 'ruby /app/update.rb &' >> /app/start.sh && \
    echo 'crond -f -d 8' >> /app/start.sh && \
    chmod +x /app/start.sh

# Set the startup script as the entry point
ENTRYPOINT ["/app/start.sh"]