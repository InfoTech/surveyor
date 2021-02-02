class DependencyCondition < ApplicationRecord
  unloadable
  include Surveyor::Models::DependencyConditionMethods
end
