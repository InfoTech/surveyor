class Survey < ApplicationRecord
  unloadable
  include Surveyor::Models::SurveyMethods  
end
