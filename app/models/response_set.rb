class ResponseSet < ApplicationRecord
  unloadable
  include Surveyor::Models::ResponseSetMethods
end