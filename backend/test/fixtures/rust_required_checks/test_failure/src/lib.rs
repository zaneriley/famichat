pub fn identity(value: u32) -> u32 {
    value
}

#[cfg(test)]
mod tests {
    use super::identity;

    #[test]
    fn fails_intentionally() {
        assert_eq!(identity(2), 3);
    }
}
