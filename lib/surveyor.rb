module Surveyor
  require 'surveyor/engine' if defined?(Rails) && Rails::VERSION::MAJOR == 4

  autoload :VERSION, 'surveyor/version'
end
require 'surveyor/common'
require 'surveyor/acts_as_response'
require 'formtastic/surveyor_builder'
# require 'surveyor/surveyor_controller_methods'
# require 'surveyor/models/survey_methods'
# Formtastic::Helpers::FormHelper.builder = Formtastic::SurveyorBuilder
require 'formtastic'
Formtastic::FormBuilder.default_text_area_height = 5
Formtastic::FormBuilder.default_text_area_width = 50
Formtastic::FormBuilder.all_fields_required_by_default = false
