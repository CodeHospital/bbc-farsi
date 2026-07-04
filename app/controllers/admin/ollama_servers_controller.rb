class Admin::OllamaServersController < Admin::BaseController
  before_action :require_admin!
  before_action :set_server, only: %i[edit update destroy toggle]

  SORT_COLUMNS = {
    "name"    => "ollama_servers.name",
    "enabled" => "ollama_servers.enabled"
  }.freeze

  def index
    column    = SORT_COLUMNS[params[:sort]] || "ollama_servers.name"
    direction = params[:dir] == "asc" ? "asc" : "desc"
    @ollama_servers = OllamaServer.order(Arel.sql("#{column} #{direction}"))
  end

  def new
    @ollama_server = OllamaServer.new
  end

  def create
    @ollama_server = OllamaServer.new(server_params)
    if @ollama_server.save
      redirect_to admin_ollama_servers_path, notice: "Server \"#{@ollama_server.name}\" added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @ollama_server.update(server_params)
      redirect_to admin_ollama_servers_path, notice: "Server \"#{@ollama_server.name}\" updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @ollama_server.destroy
    redirect_to admin_ollama_servers_path, notice: "Server removed."
  end

  def toggle
    @ollama_server.toggle!
    redirect_to admin_ollama_servers_path
  end

  private

  def set_server = @ollama_server = OllamaServer.find(params[:id])

  def server_params
    params.require(:ollama_server).permit(
      :name, :url, :enabled, :rewrite_models, :translate_models, :refine_models
    )
  end
end
