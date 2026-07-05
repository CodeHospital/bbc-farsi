# Admin/editor management of the DB-backed prompts services build LLM
# requests from (see Prompt). Deliberately not admin-only — editors are
# expected to tune prompt wording as part of the editorial workflow.
class Admin::PromptsController < Admin::BaseController
  before_action :set_prompt, only: %i[show edit update revert]

  def index
    @prompts = Prompt.includes(:current_prompt_version).order(:key)
  end

  def show
    @versions = @prompt.prompt_versions.order(number: :desc)
  end

  def edit; end

  # Editing a prompt never overwrites its content in place — a changed
  # textarea creates a new PromptVersion (and becomes current); name/description
  # are plain metadata updated directly. Task.enqueue_* always reads
  # Prompt.current_version, so the very next generated task uses this edit.
  def update
    content = params.dig(:prompt, :content).to_s
    current = @prompt.current_prompt_version

    @prompt.add_version!(content, user: current_user) if current.nil? || content != current.content
    @prompt.update!(prompt_params)

    redirect_to admin_prompt_path(@prompt), notice: "Prompt saved."
  rescue ActiveRecord::RecordInvalid => e
    @versions = @prompt.prompt_versions.order(number: :desc)
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  def revert
    version = @prompt.prompt_versions.find(params[:version_id])
    @prompt.revert_to!(version, user: current_user)
    redirect_to admin_prompt_path(@prompt), notice: "Reverted to version #{version.number}."
  end

  private

  def set_prompt = @prompt = Prompt.find(params[:id])
  def prompt_params = params.require(:prompt).permit(:name, :description)
end
