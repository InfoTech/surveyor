class Response < ApplicationRecord
  unloadable
  include ActionView::Helpers::SanitizeHelper
  include Surveyor::Models::ResponseMethods
end
