package com.example.timelineserver.timeline.feed;

import java.time.ZonedDateTime;

public class FeedInfo {

    private int feedId;
    private String imageId;
    private int uploaderId;
    private String uploaderName;

    private ZonedDateTime uploadDatetime;
    private String contents;

    public FeedInfo() {
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