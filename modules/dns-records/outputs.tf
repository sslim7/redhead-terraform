# 이 모듈이 소유한 레코드 목록. 영역에는 다른 루트 모듈이 넣은 레코드와 영역 생성 시
# 자동으로 붙는 SOA/NS 가 함께 있으므로, 이 출력은 영역의 전체 레코드가 아니다.
output "record_names" {
  description = "이 모듈이 만든 레코드의 FQDN 목록. 다른 state 의 레코드와 SOA/NS 는 포함하지 않는다"
  value = sort(concat(
    [for r in google_dns_record_set.a : r.name],
    [for r in google_dns_record_set.cname : r.name],
    [for r in google_dns_record_set.txt : r.name],
    [for r in google_dns_record_set.mx : r.name],
  ))
}
