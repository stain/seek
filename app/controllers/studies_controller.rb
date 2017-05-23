class StudiesController < ApplicationController
  include Seek::IndexPager
  include Seek::AssetsCommon

  before_filter :find_assets, only: [:index]
  before_filter :find_and_authorize_requested_item, only: %i[edit update destroy show new_object_based_on_existing_one]

  # project_membership_required_appended is an alias to project_membership_required, but is necesary to include the actions
  # defined in the application controller
  before_filter :project_membership_required_appended, only: [:new_object_based_on_existing_one]

  before_filter :check_assays_are_not_already_associated_with_another_study, only: %i[create update]

  include Seek::Publishing::PublishingCommon

  include Seek::AnnotationCommon

  include Seek::BreadCrumbs

  include Seek::IsaGraphExtensions

  def new_object_based_on_existing_one
    @existing_study = Study.find(params[:id])

    if @existing_study.can_view?
      @study = @existing_study.clone_with_associations
      unless @existing_study.investigation.can_edit?
        @study.investigation = nil
        flash.now[:notice] = "The #{t('investigation')} associated with the original #{t('study')} cannot be edited, so you need to select a different #{t('investigation')}"
      end
      render action: 'new'
    else
      flash[:error] = "You do not have the necessary permissions to copy this #{t('study')}"
      redirect_to study_path(@existing_study)
    end
  end

  def new
    @study = Study.new
    @study.create_from_asset = params[:create_from_asset]
    @study.new_link_from_assay = params[:new_link_from_assay]
    investigation = nil
    investigation = Investigation.find(params[:investigation_id]) if params[:investigation_id]

    if investigation
      if investigation.can_edit?
        @study.investigation = investigation
      else
        flash.now[:error] = "You do not have permission to associate the new #{t('study')} with the #{t('investigation')} '#{investigation.title}'."
      end
    end
    investigations = Investigation.all.select(&:can_view?)
    respond_to do |format|
      if investigations.blank?
        flash.now[:notice] = "No #{t('investigation')} available, you have to create a new one before creating your Study!"
      end
      format.html
    end
  end

  def edit
    @study = Study.find(params[:id])
    respond_to do |format|
      format.html
      format.xml
    end
  end

  def update
    @study = Study.find(params[:id])

    @study.attributes = study_params

    update_sharing_policies @study

    respond_to do |format|
      if @study.save
        update_scales @study
        update_relationships(@study, params)

        flash[:notice] = "#{t('study')} was successfully updated."
        format.html { redirect_to(@study) }
        format.xml  { head :ok }
      else
        format.html { render action: 'edit' }
        format.xml  { render xml: @study.errors, status: :unprocessable_entity }
      end
    end
  end

  def show
    @study = Study.find(params[:id])
    @study.create_from_asset = params[:create_from_asset]
    options = {:is_collection=>false, :include=>['associated']}

    respond_to do |format|
      format.html
      format.xml
      format.rdf { render template: 'rdf/show' }
      format.json {render json: JSONAPI::Serializer.serialize(@study,options)}

    end
  end

  def create

    # convert params as received by json-api to (flat) rails json
    if params.key?("data")

      params[:study] = params[:data][:attributes]

      params[:study][:project_ids] = []
      params[:relationships].each do |r,info|
        params[:study][:project_ids] << r.capitalize.constantize.where(info[:meta]).first.id
      end


      investigation_title = params[:meta][:investigation_title]
      person_email = params[:meta][:person_responsible]

      params[:study][:investigation_id] = Investigation.where(title:  investigation_title).first[:id].to_s
      params[:study][:person_responsible] = Person.where(email: person_email).first

      #Creators
      creators_arr = []
      params[:study][:creators].each { |cr|
        the_person = Person.where(email: cr).first
        creators_arr << the_person
      }
      params[:study][:creators] = creators_arr
    end

    @study = Study.new(params[:study])

    update_sharing_policies @study,params

    update_sharing_policies @study

    if @study.save
      update_scales @study
      update_relationships(@study, params)

      if @study.new_link_from_assay == 'true'
        render partial: 'assets/back_to_singleselect_parent', locals: { child: @study, parent: 'assay' }
      else
        respond_to do |format|
          flash[:notice] = "The #{t('study')} was successfully created.<br/>".html_safe
          if @study.create_from_asset == 'true'
            flash.now[:notice] << "Now you can create new #{t('assays.assay')} by clicking -Add an #{t('assays.assay')}- button".html_safe
            format.html { redirect_to study_path(id: @study, create_from_asset: @study.create_from_asset) }
          else
            format.html { redirect_to study_path(@study) }
            format.xml { render xml: @study, status: :created, location: @study }
          end
        end
      end
    else
      respond_to do |format|
        format.html { render action: 'new' }
        format.xml  { render xml: @study.errors, status: :unprocessable_entity }
      end
    end
  end

  def investigation_selected_ajax
    if (investigation_id = params[:investigation_id] && params[:investigation_id] != '0')
      investigation = Investigation.find(investigation_id)
      people = investigation.projects.collect(&:people).flatten
    end

    people ||= []

    render :update do |page|
      page.replace_html 'person_responsible_collection', partial: 'studies/person_responsible_list', locals: { people: people }
    end
  end

  def check_assays_are_not_already_associated_with_another_study
    assay_ids = params[:study][:assay_ids]
    study_id = params[:id]
    if assay_ids
      valid = !assay_ids.detect do |a_id|
        a = Assay.find(a_id)
        !a.study.nil? && a.study_id.to_s != study_id
      end
      unless valid
        unless valid
          error("Cannot add an #{t('assays.assay')} already associated with a Study", "is invalid (invalid #{t('assays.assay')})")
          return false
        end
      end
    end
  end

  private

  def study_params
    params.require(:study).permit(:title, :description, :experimentalists, :investigation_id, :person_responsible_id,
                                  :other_creators, :create_from_asset, :new_link_from_assay)
  end
end
