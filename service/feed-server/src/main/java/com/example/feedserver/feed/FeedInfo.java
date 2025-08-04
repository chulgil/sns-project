package com.example.feedserver.feed;

import java.time.ZonedDateTime;

public class FeedInfo {

    private int feedId;
    private String imageId;
    private int uploaderId;
    private String uploaderName;
    private ZonedDateTime uploadDatetime;
    private String contents;

    public FeedInfo(int feedId, String imageId, int uploaderId, String uploaderName, ZonedDateTime uploadDatetime, String contents) {
        this.feedId = feedId;
        this.imageId = imageId;
        this.uploaderId = uploaderId;
        this.uploaderName = uploaderName;
        this.uploadDatetime = uploadDatetime;
        this.contents = contents;
    }

    public FeedInfo(SocialFeed feed, String uploaderName) {
        this(feed.getFeedId(), feed.getImageId(), feed.getUploaderId(), uploaderName, feed.getUploadDatetime(), feed.getContents());
    }

    public int getFeedId() {
        return feedId;
    }

    public String getImageId() {
        return imageId;
    }

    public int getUploaderId() {
        return uploaderId;
    }

    public String getUploaderName() {
        return uploaderName;
    }

    public ZonedDateTime getUploadDatetime() {
        return uploadDatetime;
    }

    public String getContents() {
        return contents;
    }
}