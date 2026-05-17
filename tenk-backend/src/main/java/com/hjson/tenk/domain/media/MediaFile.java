package com.hjson.tenk.domain.media;

import com.hjson.tenk.domain.amount.Amount;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@Entity
@Table(name = "media_file")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class MediaFile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "file_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "amount_id", nullable = false)
    private Amount amount;

    @Column(name = "file_path", nullable = false, length = 255)
    private String filePath;

    @Column(name = "original_name", nullable = false, length = 255)
    private String originalName;

    private MediaFile(Amount amount, String filePath, String originalName) {
        this.amount = amount;
        this.filePath = filePath;
        this.originalName = originalName;
    }

    public static MediaFile create(Amount amount, String filePath, String originalName) {
        return new MediaFile(amount, filePath, originalName);
    }
}
