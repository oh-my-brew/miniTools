require "open3"

module MiniToolsReleaseMetadata
  def self.source_commit(root:, candidate_commit:)
    unless /\A[0-9a-f]{40}\z/.match?(candidate_commit.to_s)
      raise ArgumentError, "Candidate commit must be an exact SHA"
    end

    head, status = Open3.capture2e("git", "-C", root, "rev-parse", "HEAD")
    unless status.success? && head.strip == candidate_commit
      raise ArgumentError, "Checkout does not match the candidate commit"
    end

    # A shallow clone contains the raw parent header, even without the parent object.
    # Revision traversal (HEAD^) and history-aware pretty formats hide that parent.
    commit, status = Open3.capture2e("git", "-C", root, "cat-file", "commit", candidate_commit)
    raise ArgumentError, "Cannot read candidate commit object" unless status.success?

    headers = commit.split("\n\n", 2).first.lines.map(&:chomp)
    parents = headers.grep(/^parent /)
    unless parents.length == 1 && /\Aparent [0-9a-f]{40}\z/.match?(parents.first)
      raise ArgumentError, "Candidate must have exactly one parent"
    end
    parents.first.delete_prefix("parent ")
  end
end
