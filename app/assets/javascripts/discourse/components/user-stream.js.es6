import LoadMore from "discourse/mixins/load-more";
import ClickTrack from "discourse/lib/click-track";
import Post from "discourse/models/post";
import DiscourseURL from "discourse/lib/url";
import Draft from "discourse/models/draft";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { getOwner } from "discourse-common/lib/get-owner";

export default Ember.Component.extend(LoadMore, {
  _initialize: function() {
    const filter = this.get("stream.filter");
    if (filter) {
      this.set("classNames", [
        "user-stream",
        "filter-" + filter.toString().replace(",", "-")
      ]);
    }
  }.on("init"),

  loading: false,
  eyelineSelector: ".user-stream .item",
  classNames: ["user-stream"],

  _scrollTopOnModelChange: function() {
    Ember.run.schedule("afterRender", () => $(document).scrollTop(0));
  }.observes("stream.user.id"),

  _inserted: function() {
    this.bindScrolling({ name: "user-stream-view" });

    $(window).on("resize.discourse-on-scroll", () => this.scrolled());

    this.$().on("click.details-disabled", "details.disabled", () => false);
    this.$().on("click.discourse-redirect", ".excerpt a", function(e) {
      return ClickTrack.trackClick(e);
    });
  }.on("didInsertElement"),

  // This view is being removed. Shut down operations
  _destroyed: function() {
    this.unbindScrolling("user-stream-view");
    $(window).unbind("resize.discourse-on-scroll");
    this.$().off("click.details-disabled", "details.disabled");

    // Unbind link tracking
    this.$().off("click.discourse-redirect", ".excerpt a");
  }.on("willDestroyElement"),

  actions: {
    removeBookmark(userAction) {
      const stream = this.get("stream");
      Post.updateBookmark(userAction.get("post_id"), false)
        .then(() => {
          stream.remove(userAction);
        })
        .catch(popupAjaxError);
    },

    resumeDraft(item) {
      const composer = getOwner(this).lookup("controller:composer");
      if (composer.get("model.viewOpen")) {
        composer.close();
      }
      if (item.get("postUrl")) {
        DiscourseURL.routeTo(item.get("postUrl"));
      } else {
        Draft.get(item.draft_key)
          .then(d => {
            if (d.draft) {
              composer.open({
                draft: d.draft,
                draftKey: item.draft_key,
                draftSequence: d.draft_sequence
              });
            }
          })
          .catch(error => {
            popupAjaxError(error);
          });
      }
    },

    removeDraft(draft) {
      const stream = this.get("stream");
      Draft.clear(draft.draft_key, draft.sequence)
        .then(() => {
          stream.remove(draft);
        })
        .catch(error => {
          popupAjaxError(error);
        });
    },

    loadMore() {
      if (this.get("loading")) {
        return;
      }

      this.set("loading", true);
      const stream = this.get("stream");
      stream.findItems().then(() => {
        this.set("loading", false);
        this.get("eyeline").flushRest();
      });
    }
  }
});
