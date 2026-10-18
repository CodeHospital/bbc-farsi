# Word-level diff of two strings, for showing reviewers exactly what a
# pending edit changes. Returns runs of [operation, text] where operation is
# :equal, :delete or :insert. Whitespace is kept as its own token so the
# pieces concatenate back to the original/new text.
#
# Plain LCS (no gem). Texts too large for the O(n·m) table fall back to a
# whole-text delete + insert, which the view renders as before/after.
class TextDiff
  MAX_TABLE_CELLS = 4_000_000

  def self.word_diff(old_text, new_text) = new(old_text, new_text).operations

  def initialize(old_text, new_text)
    @old_tokens = tokenize(old_text)
    @new_tokens = tokenize(new_text)
  end

  def operations
    return [] if @old_tokens.empty? && @new_tokens.empty?
    return whole_text_replacement if @old_tokens.size * @new_tokens.size > MAX_TABLE_CELLS

    merge_runs(lcs_operations)
  end

  private

  def tokenize(text) = text.to_s.scan(/\s+|[^\s]+/)

  def whole_text_replacement
    merge_runs([ [ :delete, @old_tokens.join ], [ :insert, @new_tokens.join ] ].reject { |_, text| text.empty? })
  end

  # Classic LCS table filled from the end so the walk below goes forwards.
  def lcs_operations
    old_count = @old_tokens.size
    new_count = @new_tokens.size
    common_lengths = Array.new(old_count + 1) { Array.new(new_count + 1, 0) }

    (old_count - 1).downto(0) do |old_index|
      (new_count - 1).downto(0) do |new_index|
        common_lengths[old_index][new_index] =
          if @old_tokens[old_index] == @new_tokens[new_index]
            common_lengths[old_index + 1][new_index + 1] + 1
          else
            [ common_lengths[old_index + 1][new_index], common_lengths[old_index][new_index + 1] ].max
          end
      end
    end

    diff_operations = []
    old_index = new_index = 0
    while old_index < old_count && new_index < new_count
      if @old_tokens[old_index] == @new_tokens[new_index]
        diff_operations << [ :equal, @old_tokens[old_index] ]
        old_index += 1
        new_index += 1
      elsif common_lengths[old_index + 1][new_index] >= common_lengths[old_index][new_index + 1]
        diff_operations << [ :delete, @old_tokens[old_index] ]
        old_index += 1
      else
        diff_operations << [ :insert, @new_tokens[new_index] ]
        new_index += 1
      end
    end
    @old_tokens[old_index..].each { |token| diff_operations << [ :delete, token ] }
    @new_tokens[new_index..].each { |token| diff_operations << [ :insert, token ] }
    diff_operations
  end

  def merge_runs(diff_operations)
    diff_operations.each_with_object([]) do |(operation, text), merged|
      if merged.last && merged.last[0] == operation
        merged.last[1] += text
      else
        merged << [ operation, +text ]
      end
    end
  end
end
