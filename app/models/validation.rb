class Validation < ApplicationRecord
  unloadable
  include Surveyor::Models::ValidationMethods
end