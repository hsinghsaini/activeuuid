class UuidArticle < ActiveRecord::Base
  prepend ActiveUUID::UUID
end
