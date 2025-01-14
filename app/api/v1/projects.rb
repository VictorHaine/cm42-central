class V1::Projects < Grape::API
  resource :projects do
    helpers do
      def authorize_project!
        return unless current_team
        @allowed_projects = current_team.projects.pluck(:slug)

        return if !params[:slug] || @allowed_projects.include?(params[:slug])

        error!('Unauthorized. Invalid team.', 401)
      end

      def load_projects(archiveds)
        return Project.all if archiveds

        Project.not_archived
      end

      def allowed_update_params
        ActionController::Parameters.new(params).require(:project).permit(
          :name, :default_velocity, :point_scale,
          :iteration_start_day, :mail_reports
        )
      end
    end

    before do
      authenticate!
      authorize_project!
    end

    desc 'Return all projects', tags: ['project']
    params do
      optional :archiveds, type: Boolean, default: false
    end
    paginate
    get '/' do
      projects = load_projects(params[:archiveds])
      projects = projects.where(slug: @allowed_projects) if @allowed_projects

      present paginate(projects), with: Entities::Project
    end

    desc 'Return the specified project', tags: ['project']
    get '/:slug' do
      project = Project.find_by(slug: params[:slug])

      present project, with: Entities::Project, type: :full
    end

    desc 'Return the specified project with analysis', tags: ['project']
    params do
      requires :since, type: Integer
      optional :current_time, type: DateTime
    end
    get '/:slug/analysis' do
      project = Project.not_archived.find_by(slug: params[:slug])
      current_time = params[:current_time] || Time.current
      params[:since].months.ago

      if project
        iteration = IterationService.new(project, current_time: current_time)
      end

      present iteration, with: Entities::ProjectAnalysis
    end

    desc 'Return the stories of a specified project', tags: ['project']
    params do
      optional :state,
               type: Symbol,
               values: %i[done in_progress backlog chilly_bin],
               default: :backlog
      optional :created_at, type: DateTime
      optional :accepted_at, type: DateTime
    end
    paginate
    get '/:slug/stories' do
      project = Project.includes(:stories).find_by(slug: params[:slug])

      stories = project.stories.send(params[:state])
      stories = stories.where('created_at >= ?', params[:created_at]) if params[:created_at]
      stories = stories.where('accepted_at >= ?', params[:accepted_at]) if params[:accepted_at]

      present paginate(stories), with: Entities::Story
    end

    desc 'Return all users of a specified project', tags: ['project']
    paginate
    get '/:slug/users' do
      project = Project.includes(memberships: :user).find_by(slug: params[:slug])
      users = project.users

      present paginate(users), with: Entities::User
    end

    desc 'Update a specified project', tags: ['project']
    params do
      requires :slug, type: String
    end
    put '/:slug' do
      project = Project.find_by(slug: params[:slug])
      project.update(allowed_update_params)

      present project, with: Entities::Project, type: :full
    end
  end
end
