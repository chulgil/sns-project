package com.example.userserver.follow;

import com.example.userserver.user.UserInfo;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class FollowService {

    private FollowRepository followRepository;

    public FollowService(FollowRepository followRepository) {
        this.followRepository = followRepository;
    }

    public boolean isFollow(int userId, int followerId) {
        Follow follow = followRepository.findByUserIdAndFollowerId(userId, followerId);
        return follow != null;
    }

    @Transactional
    public Follow followUser(int userId, int followerId) {
        if (isFollow(userId, followerId)) {
            return null;
        }

        return followRepository.save(new Follow(userId, followerId));
    }

    @Transactional
    public boolean unfollowUser(int userId, int followerId) {
        Follow follow = followRepository.findByUserIdAndFollowerId(userId, followerId);
        if (follow == null) {
            return false;
        }

        followRepository.delete(follow);
        return true;
    }

    public List<UserInfo> listFollower(int userId) {
        return followRepository.findFollowingByUserId(userId);
    }

    public List<UserInfo> listFollowing(int userId) {
        return followRepository.findFollowingByUserId(userId);
    }

}