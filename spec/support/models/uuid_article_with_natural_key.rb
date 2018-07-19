class UuidArticleWithNaturalKey < ActiveRecord::Base
  prepend ActiveUUID::UUID
  self.table_name = 'uuid_articles'
  natural_key :title
end
