class About
  include ActiveModel::Serialization

  attr_accessor :moderators,
                :admins

  def version
    Discourse::VERSION::STRING
  end

  def title
    SiteSetting.title
  end

  def locale
    SiteSetting.default_locale
  end

  def description
    SiteSetting.site_description
  end

  def moderators
    @moderators ||= User.where(moderator: true)
                        .where.not(id: Discourse::SYSTEM_USER_ID)
  end

  def admins
    @admins ||= User.where(admin: true)
                    .where.not(id: Discourse::SYSTEM_USER_ID)
  end

  def stats
    @stats ||= {
       topic_count: Topic.listable_topics.count,
       post_count: Post.count,
       user_count: User.count,
       topics_7_days: Topic.listable_topics.where('created_at > ?', 7.days.ago).count,
       posts_7_days: Post.where('created_at > ?', 7.days.ago).count,
       users_7_days: User.where('created_at > ?', 7.days.ago).count,
       like_count: UserAction.where(action_type: UserAction::LIKE).count,
       likes_7_days: UserAction.where(action_type: UserAction::LIKE)
                               .where("created_at > ?", 7.days.ago)
                               .count
    }
  end

end
