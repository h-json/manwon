package com.hjson.manwon.domain.user;

import com.hjson.manwon.common.exception.BusinessException;
import com.hjson.manwon.common.exception.ErrorCode;
import com.hjson.manwon.domain.auth.RefreshTokenRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class UserService {

    private final UserRepository userRepository;
    private final RefreshTokenRepository refreshTokenRepository;

    public User getActiveUser(Long userId) {
        return userRepository.findByIdAndDeletedFalse(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.USER_NOT_FOUND));
    }

    @Transactional
    public void updateNickname(Long userId, String nickname) {
        User user = getActiveUser(userId);
        user.updateProfile(null, nickname);
    }

    @Transactional
    public void withdraw(Long userId) {
        User user = getActiveUser(userId);
        if (user.isDeleted()) {
            throw new BusinessException(ErrorCode.USER_ALREADY_WITHDRAWN);
        }
        user.withdraw();
        refreshTokenRepository.revokeAllByUserId(userId);
    }
}
