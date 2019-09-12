class Dependency < ApplicationRecord
  unloadable
  include Surveyor::Models::DependencyMethods
end
