package com.example.timelineserver.timeline;

import com.example.timelineserver.timeline.feed.FeedInfo;

import java.time.ZonedDateTime;

public class SocialPost {

    private int feedId;
    private String imageId;
    private String uploaderName;
    private int uploaderId;

    private ZonedDateTime uploadDatetime;
    private String contents;
    private Long likes;

    public SocialPost(FeedInfo post, Long likes) {
        this(post.getFeedId(), post.getImageId(), post.getUploaderName(), post.getUploaderId(), post.getUploadDatetime(), post.getContents(), likes == null ? 0 : likes);
    }

    public SocialPost(int feedId, String imageId, String uploaderName, int uploaderId, ZonedDateTime uploadDatetime, String contents, Long likes) {
        this.feedId = feedId;
        this.imageId = imageId;
        this.uploaderName = uploaderName;
        this.uploaderId = uploaderId;
        this.uploadDatetime = uploadDatetime;
        this.contents = contents;
        this.likes = likes;
    }

    public int getFeedId() {
        return feedId;
    }

    public String getImageId() {
        return imageId;
    }

    public String getUploaderName() {
        return uploaderName;
    }

    public int getUploaderId() {
        return uploaderId;
    }

    public ZonedDateTime getUploadDatetime() {
        return uploadDatetime;
    }

    public String getContents() {
        return contents;
    }

    public Long getLikes() {
        return likes;
    }
}
