package com.example.userserver.follow;

import com.example.userserver.user.UserInfo;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/follows")
public class FollowController {

    private final FollowService followService;

    public FollowController(FollowService followService) {
        this.followService = followService;
    }

    @GetMapping("/followers/{userId}")
    public List<UserInfo> listFollowers(@PathVariable("userId") int userId) {
        return followService.listFollower(userId);
    }

    @GetMapping("/followings/{userId}")
    public List<UserInfo> listFollowings(@PathVariable("userId") int userId) {
        return followService.listFollowing(userId);
    }

    @GetMapping("/follow/{userId}/{followerId}")
    public boolean isFollow(@PathVariable("userId") int userId, @PathVariable("followerId") int followerId) {
        return followService.isFollow(userId, followerId);
    }

    @PostMapping("/follow")
    public Follow followUser(@RequestBody FollowRequest followRequest) {
        Follow follow = followService.followUser(followRequest.getUserId(), followRequest.getFollowerId());
        return follow;
    }

    @PostMapping("/unfollow")
    public Boolean unfollowUser(@RequestBody FollowRequest unfollowRequest) {
        return followService.unfollowUser(unfollowRequest.getUserId(), unfollowRequest.getFollowerId());
    }
}