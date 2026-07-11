require "test_helper"
require "telegram/bot"

class TelegramAdminNotifierTest < ActiveSupport::TestCase
  FakeMessage = Struct.new(:message_id)

  setup do
    stub_telegram_admin_bot_config
    @fake_bot, @sent, @edited, @answered = build_fake_bot
  end

  teardown { restore_telegram_admin_bot_config }

  test "notify is a no-op when TelegramAdminBot is disabled" do
    stub_telegram_admin_bot_config(bot_token: nil)
    translation = create_translation

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    assert_empty @sent
    assert_equal 0, TelegramAdminNotification.count
  end

  test "notify sends a Markdown message with the main menu and records a notification row" do
    translation = create_translation(attrs: { translated_title: "عنوان خبر", translated_body: "متن خبر" })

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    assert_equal "12345",    @sent[:chat_id]
    assert_equal "Markdown", @sent[:parse_mode]
    assert_includes @sent[:text], "عنوان خبر"
    assert_kind_of Telegram::Bot::Types::InlineKeyboardMarkup, @sent[:reply_markup]

    notification = TelegramAdminNotification.last
    assert_equal translation, notification.translation
    assert_equal "999",  notification.message_id.to_s
    assert_equal "sent", notification.status
  end

  test "notify includes a source link button but not portal links when app_base_url isn't configured" do
    translation = create_translation

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    buttons = @sent[:reply_markup].inline_keyboard.flatten
    link_buttons = buttons.select { |b| b.url.present? }
    assert_equal [ translation.article.url ], link_buttons.map(&:url)
  end

  test "notify includes English and Persian portal link buttons when app_base_url is configured" do
    stub_llmarkt_config
    translation = create_translation

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    buttons = @sent[:reply_markup].inline_keyboard.flatten
    assert(buttons.any? { |b| b.url == "https://app.test/en/news/#{translation.seo_param}" })
    assert(buttons.any? { |b| b.url == "https://app.test/news/#{translation.seo_param}" })
  ensure
    restore_llmarkt_config
  end

  test "handle_callback rewrite enqueues a rewrite task and records the action" do
    create_rewrite_server
    translation  = create_translation
    notification = create_notification(translation)

    assert_difference -> { Task.where(kind: "rewrite").count }, 1 do
      ::Telegram::Bot::Client.stub(:new, @fake_bot) do
        TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "rewrite"))
      end
    end

    assert_includes @answered[:text], "Rewrite queued"
    assert_equal "actioned", notification.reload.status
    assert_equal "rewrite",  notification.last_action
    assert_equal "editor1",  notification.actioned_by
  end

  test "handle_callback rewrite without a configured server reports failure and does not enqueue" do
    translation = create_translation
    create_notification(translation)

    assert_no_difference -> { Task.count } do
      ::Telegram::Bot::Client.stub(:new, @fake_bot) do
        TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "rewrite"))
      end
    end

    assert_includes @answered[:text], "No Ollama servers"
  end

  test "handle_callback retranslate enqueues a translate task" do
    translation = create_translation
    create_notification(translation)

    assert_difference -> { Task.where(kind: "translate").count }, 1 do
      ::Telegram::Bot::Client.stub(:new, @fake_bot) do
        TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "retranslate"))
      end
    end

    assert_includes @answered[:text], "Retranslation queued"
  end

  test "handle_callback refine enqueues a refine task when a server is configured" do
    OllamaServer.create!(name: "Local", url: "http://localhost:11434", refine_models: "qwen3:14b")
    translation = create_translation
    create_notification(translation)

    assert_difference -> { Task.where(kind: "refine").count }, 1 do
      ::Telegram::Bot::Client.stub(:new, @fake_bot) do
        TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "refine"))
      end
    end

    assert_includes @answered[:text], "Refine queued"
  end

  test "handle_callback post publishes to the given channel" do
    channel      = create_channel
    translation  = create_translation
    notification = create_notification(translation)

    poster_fake_api = Object.new
    poster_fake_api.define_singleton_method(:send_message) { |_opts| FakeMessage.new(1) }
    poster_fake_bot = Object.new
    poster_fake_bot.define_singleton_method(:api) { poster_fake_api }

    dispatch = ->(token) { token == channel.token ? poster_fake_bot : @fake_bot }
    ::Telegram::Bot::Client.stub(:new, dispatch) do
      TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "post", extra_id: channel.id))
    end

    post = TelegramPost.find_by(translation:, telegram_channel: channel)
    assert_equal "posted", post.status
    assert_equal "posted", translation.article.reload.status
    assert_includes @answered[:text], "Posted to #{channel.name}"
    assert_equal "actioned", notification.reload.status
  end

  test "handle_callback portal toggles archived on and off" do
    translation = create_translation(attrs: { archived: false })
    create_notification(translation)

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "portal"))
    end
    assert translation.reload.archived?
    assert_includes @answered[:text], "Unpublished"

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "portal"))
    end
    assert_not translation.reload.archived?
    assert_includes @answered[:text], "Republished"
  end

  test "handle_callback manual_edit toggles needs_manual_edit on and off" do
    translation = create_translation(attrs: { needs_manual_edit: false })
    create_notification(translation)

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "manual_edit"))
    end
    assert translation.reload.needs_manual_edit?

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "manual_edit"))
    end
    assert_not translation.reload.needs_manual_edit?
  end

  test "handle_callback channels renders a channel submenu without changing notification status" do
    create_channel(name: "Main channel")
    translation  = create_translation
    notification = create_notification(translation)

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.handle_callback(callback_query_for(translation, action: "channels"))
    end

    assert_kind_of Telegram::Bot::Types::InlineKeyboardMarkup, @edited[:reply_markup]
    button_texts = @edited[:reply_markup].inline_keyboard.flatten.map(&:text)
    assert(button_texts.any? { |t| t.include?("Main channel") })
    assert_equal "sent", notification.reload.status
  end

  test "main menu publish button opens the channel submenu when several channels are enabled" do
    create_channel(name: "Channel A")
    create_channel(name: "Channel B", channel_id: "@channelb")
    translation = create_translation

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    publish = @sent[:reply_markup].inline_keyboard.flatten.find { |b| b.callback_data.to_s.start_with?("channels:", "post:") }
    assert_equal "channels:#{translation.id}", publish.callback_data
    assert_equal "📤 انتشار در کانال تلگرام", publish.text
  end

  test "publish button posts straight to the only enabled channel without a submenu, and does not auto-publish" do
    channel     = create_channel(name: "Only Channel")
    create_channel(name: "Disabled", channel_id: "@disabled", enabled: false)
    translation = create_translation

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    # Nothing is posted just by notifying — the admin still confirms with a tap.
    assert_equal 0, TelegramPost.count

    publish = @sent[:reply_markup].inline_keyboard.flatten.find { |b| b.callback_data.to_s.start_with?("channels:", "post:") }
    assert_equal "post:#{translation.id}:#{channel.id}", publish.callback_data
    assert_equal "📤 انتشار در Only Channel", publish.text
  end

  test "publish button opens the channel submenu and does not auto-publish when several channels are enabled" do
    translation = create_translation
    create_channel(name: "Channel A")
    create_channel(name: "Channel B", channel_id: "@channelb")

    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.notify(translation)
    end

    assert_equal 0, TelegramPost.count

    publish = @sent[:reply_markup].inline_keyboard.flatten.find { |b| b.callback_data.to_s.start_with?("channels:", "post:") }
    assert_equal "channels:#{translation.id}", publish.callback_data
  end

  test "handle_callback for a translation that no longer exists answers without raising" do
    ::Telegram::Bot::Client.stub(:new, @fake_bot) do
      TelegramAdminNotifier.handle_callback(callback_query_for(nil, action: "rewrite", translation_id: 999_999))
    end

    assert_includes @answered[:text], "no longer exists"
  end

  private

  # Returns [fake_bot, sent, edited, answered] — the last three are Hash
  # instances mutated in place by the fake API's singleton methods, so
  # assertions in the test body (a different `self`) see the same updates.
  def build_fake_bot
    sent     = {}
    edited   = {}
    answered = {}

    fake_api = Object.new
    fake_api.define_singleton_method(:send_message)         { |opts| sent.replace(opts); FakeMessage.new(999) }
    fake_api.define_singleton_method(:edit_message_text)     { |opts| edited.replace(opts); true }
    fake_api.define_singleton_method(:answer_callback_query) { |opts| answered.replace(opts); true }

    fake_bot = Object.new
    fake_bot.define_singleton_method(:api) { fake_api }

    [ fake_bot, sent, edited, answered ]
  end

  def create_rewrite_server
    OllamaServer.create!(name: "Local", url: "http://localhost:11434", rewrite_models: "qwen3:14b")
  end

  def create_notification(translation, message_id: 555, chat_id: "12345")
    TelegramAdminNotification.create!(translation:, chat_id:, message_id:, status: "sent")
  end

  def callback_query_for(translation, action:, extra_id: nil, translation_id: nil, message_id: 555, chat_id: "12345")
    id = translation_id || translation&.id
    {
      "id" => "cbq-1",
      "data" => [ action, id, extra_id ].compact.join(":"),
      "from" => { "id" => 42, "username" => "editor1" },
      "message" => { "message_id" => message_id, "chat" => { "id" => chat_id } }
    }
  end
end
