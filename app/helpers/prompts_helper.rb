module PromptsHelper
  def prompt_version_actor(version)
    version.user&.username || "System (seed)"
  end
end
