extension PatternUtils on Pattern {
  bool equals(Pattern other) {
    return switch ((this, other)) {
      (String self, String other) => self == other,
      (String self, Pattern other) => other.allMatches(self).isNotEmpty,
      (Pattern self, String other) => self.allMatches(other).isNotEmpty,
      _ => this == other,
    };
  }
}

extension NullablePatternUtils on Pattern? {
  bool equals(Pattern? other) {
    return switch ((this, other)) {
      (Pattern pattern, _) => other?.equals(pattern) == true,
      (_, Pattern other) => this?.equals(other) == true,
      _ => this == other,
    };
  }
}
