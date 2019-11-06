module Surveyor
  module SurveyorControllerMethods
    def self.included(base)
      base.send :before_action, :get_current_user, only: [:new, :create]
      base.send :before_action, :determine_if_javascript_is_enabled, only: [:create, :update]
      base.send :layout, 'surveyor_default'
    end

    # Actions
    def new
      @surveys = Survey.find(:all)
      @title = "You can take these surveys"
      redirect_to surveyor_index unless surveyor_index == available_surveys_path
    end

    def create
      @survey = Survey.find_by_access_code(other_params[:survey_code])
      @response_set = ResponseSet.find_by_survey_id_and_user_id(@survey.id, @current_user.id) unless @current_user.nil? || @survey.nil?
      @response_set ||= ResponseSet.create(:survey => @survey, :user_id => (@current_user.nil? ? @current_user : @current_user.id))
      if (@survey && @response_set)
        redirect_to(edit_my_survey_path(:survey_code => @survey.access_code, :response_set_code  => @response_set.access_code))
      else
        flash[:notice] = t('surveyor.Unable_to_find_that_survey')
        redirect_to surveyor_index
      end
    end

    def show
      @response_set = ResponseSet.find_by_access_code(other_params[:response_set_code], :include => {:responses => [:question, :answer]})
      if @response_set
        @survey = @response_set.survey
        respond_to do |format|
          format.html #{render :action => :show}
          format.csv {
            send_data(@response_set.to_csv, :type => 'text/csv; charset=utf-8; header=present',:filename => "#{@response_set.updated_at.strftime('%Y-%m-%d')}_#{@response_set.access_code}.csv")
          }
        end
      else
        flash[:notice] = t('surveyor.unable_to_find_your_responses')
        redirect_to surveyor_index
      end
    end

    def edit
      @response_set = ResponseSet.includes({:responses => [:question, :answer]}).find_by_access_code(other_params[:response_set_code])
      if @response_set
        @survey = Survey.with_sections.find_by_id(@response_set.survey_id)
        @sections = @survey.sections
        if other_params[:section]
          @section = @sections.with_includes.find(section_id_from(other_params[:section])) || @sections.with_includes.first
        else
          @section = @sections.with_includes.first
        end
        set_dependents
      else
        flash[:notice] = t('surveyor.unable_to_find_your_responses')
        redirect_to surveyor_index
      end
    end

    def update
      saved = false
      @errors = []
      ActiveRecord::Base.transaction do
        @response_set = ResponseSet.includes({:responses => :answer}).lock.find_by_access_code(other_params[:response_set_code])
        unless @response_set.blank?

          response_params.each do |res| 
            if res[1][:id].nil?
              answered = Response.find_by_question_id_and_response_set_id(res[1][:question_id], @response_set.id)
              if answered.present?
                res[1][:id] = answered[:id]
              end
            end
          end

          @errors = Response.validate(response_params, @response_set)

          # Remove know invalid responses from update call, to be handled separately by validation
          @errors.each do |error|
            response_params.reject!{ |k,v| v[:question_id] == error[:question] }
          end
          saved = @response_set.update_attributes(:responses_attributes => ResponseSet.to_savable(response_params))
          @response_set.complete! if saved && other_params[:finish] && @errors.empty? && @response_set.mandatory_questions_complete?
          saved &= @response_set.save
        end
      end

      if saved && other_params[:finish]
        return redirect_with_message(surveyor_finish, :success, t('surveyor.completed_survey')) if @errors.empty?

        flash[:validation_errors] = @errors
        return redirect_with_message(request.referrer, :error, t('surveyor.incomplete_section'))
      end

      respond_to do |format|
        format.html do
          byebug
          unless @errors.empty? || returning_to_previous_section?(other_params[:current_section], other_params[:section])
            flash[:validation_errors] = @errors
            redirect_with_message(request.referrer, :error, t('surveyor.incomplete_section')) and return
          end

          if @response_set.blank?
            return redirect_with_message(available_surveys_path, :notice, t('surveyor.unable_to_find_your_responses'))
          else
            flash[:notice] = t('surveyor.unable_to_update_survey') unless saved
            redirect_to edit_my_survey_path(:anchor => anchor_from(other_params[:section]), :section => section_id_from(other_params[:section]))
          end
        end

        format.js do
          ids, remove, question_ids = {}, {}, []
          ResponseSet.trim_for_lookups(response_params).each do |k,v|
            v[:answer_id].reject!(&:blank?) if v[:answer_id].is_a?(Array)
            ids[k] = @response_set.responses.where(v).order("created_at DESC").first.id if !v.has_key?("id")
            remove[k] = v["id"] if v.has_key?("id") && v.has_key?("_destroy")
            question_ids << v["question_id"]
          end

          render :json => {:errors => @errors, "ids" => ids, "remove" => remove, "correct" => question_ids}.merge(@response_set.reload.all_dependencies(question_ids)).to_json
        end
      end
    end

    private

    # Filters
    def get_current_user
      @current_user = self.respond_to?(:current_user) ? self.current_user : nil
    end

    # Params: the name of some submit buttons store the section we'd like to go to. for repeater questions, an anchor to the repeater group is also stored
    # e.g. other_params[:section] = {"1"=>{"question_group_1"=>"<= add row"}}
    def section_id_from(p)
      p.respond_to?(:keys) ? p.keys.first : p
    end

    def anchor_from(p)
      p.respond_to?(:keys) && p[p.keys.first].respond_to?(:keys) ? p[p.keys.first].keys.first : nil
    end

    def surveyor_index
      available_surveys_path
    end
    def surveyor_finish
      available_surveys_path
    end

    def redirect_with_message(path, message_type, message)
      respond_to do |format|
        format.html do
          flash[message_type] = message if !message.blank? and !message_type.blank?
          redirect_to path
        end
        format.js do
          render :text => message, :status => 403
        end
      end
    end

    def returning_to_previous_section?(current_section, destination_section)
      return false if current_section.nil? && destination_section.nil?
      return current_section.to_i > section_id_from(destination_section).to_i
    end

    ##
    # @dependents are necessary in case the client does not have javascript enabled
    # Whether or not javascript is enabled is determined by a hidden field set in the surveyor/edit.html form 
    def set_dependents
      if session[:surveyor_javascript] && session[:surveyor_javascript] == "enabled"
        @dependents = []
      else
        @dependents = get_unanswered_dependencies_minus_section_questions
      end
    end

    def get_unanswered_dependencies_minus_section_questions
      @response_set.unanswered_dependencies - @section.questions || []
    end

    ##
    # If the hidden field surveyor_javascript_enabled is set to true
    # cf. surveyor/edit.html.haml
    # the set the session variable [:surveyor_javascript] to "enabled"
    def determine_if_javascript_is_enabled
      if other_params[:surveyor_javascript_enabled] && other_params[:surveyor_javascript_enabled].to_s == "true"
        session[:surveyor_javascript] = "enabled"
      else
        session[:surveyor_javascript] = "not_enabled"
      end
    end

    def response_params
      @response_params = params.require(:r).permit!.to_h
    end

    def other_params
      # params.permit(:survey_code, :response_set_code, :current_section, :finish, :surveyor_javascript_enabled, :utf8, :_method, :authenticity_token, r: {}, section: {}).to_h
      # for some reason the above permitted params don't permit :section, and :r properly....somehow, so fuck it:
      params.permit!
    end
  end
end
