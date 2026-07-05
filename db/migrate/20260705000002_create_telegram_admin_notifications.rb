class CreateTelegramAdminNotifications < ActiveRecord::Migration[8.0]
  def change
    add_column :translations, :needs_manual_edit, :boolean, default: false, null: false

    create_table :telegram_admin_notifications do |t|
      t.references :translation, null: false, foreign_key: true
      t.string :chat_id, null: false
      t.bigint :message_id, null: false
      t.string :status, default: "sent", null: false
      t.string :last_action
      t.string :actioned_by
      t.datetime :actioned_at

      t.timestamps
    end
  end
end
