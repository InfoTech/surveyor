class SurveySection < ApplicationRecord
  unloadable
  include Surveyor::Models::SurveySectionMethods
end

