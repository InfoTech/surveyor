class Answer < ApplicationRecord
  unloadable
  include Surveyor::Models::AnswerMethods
end
