module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin

    def connect
      self.current_admin = verify_admin_session!
    end

    private

    def verify_admin_session!
      if request.session[:admin_logged_in] == true
        "admin"
      else
        reject_unauthorized_connection
      end
    end
  end
end
