class UserSessionsController < ApplicationController
  before_action :require_no_user, only: [:new]
  def new
    @title = I18n.t('user_sessions_controller.log_in')
  end

  def create
    auth = request.env['omniauth.auth']
    if auth
      # User successfully completed oauth signin on third-party
      handle_social_login_flow(auth)
    else
      # User clicked on login button on site
      handle_site_login_flow
    end
  end

  def handle_site_login_flow
    username = params[:user_session][:username] if params[:user_session]
    u = User.find_by(username: username)
    if u && u.password_checker != 0
      n = u.password_checker
      hash = { 1 => "Facebook", 2 => "Github", 3 => "Google", 4 => "Twitter"  }
      s = "This account doesn't have a password set. It may be logged in with " + hash[n] + " account, or you can set a new password via Forget password feature"
      flash[:error] = s
      redirect_to '/'
    else
      params[:user_session][:username] = params[:openid] if params[:openid] # second runthrough must preserve username
      @user = User.find_by(username: username)
      # try finding by email, if that exists
      if @user.nil? && !User.where(email: username).empty?
        @user = User.find_by(email: username)
        params[:user_session][:username] = @user.username
      end
      return_to = session[:openid_return_to] || session[:return_to] || params[:return_to]
      if @user.nil?
        hash_params = ""
        unless params[:hash_params].to_s.empty?
          hash_params = URI.parse("#" + params[:hash_params]).to_s
        end
        flash[:warning] = "There is nobody in our system by that name, are you sure you have the right username?"
        redirect_to params[:return_to]
      elsif params[:user_session].nil? || @user&.status == 1
        # an existing Rails user
        return_to = return_to || '/dashboard'
        if params[:user_session].nil? || @user
          if @user&.crypted_password.nil? # the user has not created a pwd in the new site
            params[:user_session][:openid_identifier] = 'https://old.publiclab.org/people/' + username + '/identity' if username
            params[:user_session].delete(:password)
            params[:user_session].delete(:username)
            params[:openid] = username # pack up username for second runthrough
          end
          @user_session = UserSession.new(username: params[:user_session][:username],
                                          password: params[:user_session][:password],
                                          remember_me: params[:user_session][:remember_me])
          @user_session.save do |result|
            if result
              hash_params = ""
              unless params[:hash_params].to_s.empty?
                hash_params = URI.parse("#" + params[:hash_params]).to_s
              end
              # replace this with temporarily saving pwd in session,
              # and automatically saving it in the user record after login is completed
              if current_user.crypted_password.nil? # the user has not created a pwd in the new site
                flash[:warning] = I18n.t('user_sessions_controller.create_password_for_new_site')
                redirect_to '/profile/edit'
              else
                flash[:notice] = I18n.t('user_sessions_controller.logged_in')
                if session[:openid_return_to] # for openid login, redirects back to openid auth process
                  return_to = session[:openid_return_to]
                  session[:openid_return_to] = nil
                  redirect_to return_to + hash_params
                elsif session[:return_to]
                  return_to = session[:return_to]
                  if return_to == '/login'
                    return_to = '/dashboard'
                  end
                  session[:return_to] = nil
                  redirect_to return_to + hash_params
                elsif params[:return_to]
                  redirect_to params[:return_to] + hash_params
                else
                  redirect_to '/dashboard'
                end
              end
            else
                # Login failed; probably bad password.
                # Errors will display on login form:
              render action: 'new'
            end
          end
        else # not a native user
          flash[:warning] = I18n.t('user_sessions_controller.sign_up_to_join')
          redirect_to '/signup'
        end
      elsif params[:user_session].nil? || @user&.status == 5
        flash[:error] = I18n.t('user_sessions_controller.user_has_been_moderated', username: @user.username).html_safe
        redirect_to '/'
      else
        flash[:error] = I18n.t('user_sessions_controller.user_has_been_banned', username: @user.username).html_safe
        redirect_to '/'
      end
    end
  end

  def destroy
    @user_session = UserSession.find
    @user_session.destroy
    flash[:notice] = I18n.t('user_sessions_controller.logged_out')
    prev_uri = URI(request.referer || "").path
    redirect_to prev_uri + '?_=' + Time.current.to_i.to_s
  end

  def logout_remotely
    current_user&.reset_persistence_token!
    flash[:notice] = I18n.t('user_sessions_controller.logged_out')
    prev_uri = URI(request.referer || "").path
    redirect_to prev_uri + '?_=' + Time.current.to_i.to_s
  end

  def index
    redirect_to '/dashboard'
  end
end
