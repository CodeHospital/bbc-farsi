module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin

    def connect
      self.current_admin = verify_admin_session!
    end

    private

    def verify_admin_session!
      user_id = request.session[:user_id]
      if user_id.present? && User.exists?(id: user_id)
        "admin"
      else
        reject_unauthorized_connection
      end
    end
  end
end
