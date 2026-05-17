package com.hjson.tenk.domain.media;

import com.hjson.tenk.common.api.ApiResponse;
import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.security.CurrentUserId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Media", description = "영상 파일 API")
@RestController
@RequestMapping("/api/media")
@RequiredArgsConstructor
public class MediaController {

    private final MediaFileRepository mediaFileRepository;
    private final LocalFileStorage storage;

    @Operation(summary = "영상 파일 다운로드/스트리밍")
    @GetMapping("/{fileId}")
    public ResponseEntity<Resource> download(@CurrentUserId Long userId,
                                             @PathVariable Long fileId) throws IOException {
        MediaFile mediaFile = mediaFileRepository.findById(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND));
        Long ownerId = mediaFile.getAmount().getChallenge().getUser().getId();
        if (!ownerId.equals(userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN);
        }

        Path filePath = storage.resolve(mediaFile.getFilePath());
        if (!Files.exists(filePath)) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND);
        }
        Resource resource = new UrlResource(filePath.toUri());
        String contentType = Files.probeContentType(filePath);
        String encodedFilename = URLEncoder.encode(mediaFile.getOriginalName(), StandardCharsets.UTF_8)
                .replace("+", "%20");
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "inline; filename*=UTF-8''" + encodedFilename)
                .contentType(contentType != null ? MediaType.parseMediaType(contentType) : MediaType.APPLICATION_OCTET_STREAM)
                .body(resource);
    }

    @Operation(summary = "메타데이터 조회")
    @GetMapping("/{fileId}/meta")
    public ApiResponse<MediaMeta> meta(@CurrentUserId Long userId, @PathVariable Long fileId) {
        MediaFile mediaFile = mediaFileRepository.findById(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND));
        Long ownerId = mediaFile.getAmount().getChallenge().getUser().getId();
        if (!ownerId.equals(userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN);
        }
        return ApiResponse.ok(new MediaMeta(
                mediaFile.getId(),
                mediaFile.getOriginalName(),
                mediaFile.getAmount().getId()));
    }

    public record MediaMeta(Long fileId, String originalName, Long amountId) {}
}
