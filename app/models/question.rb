class Question < ApplicationRecord
  unloadable
  include Surveyor::Models::QuestionMethods
end