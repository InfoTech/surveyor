class QuestionGroup < ApplicationRecord
  unloadable
  include Surveyor::Models::QuestionGroupMethods
  
end
