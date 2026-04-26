/**
 * 环境变量
 */
(function (window) {
  window.env =
    {
  "$showNewAIFeatures": true,
  "email": "mailto:developer@huawei.com",
  "openGuidelines": true,
  "$useNewStyle": true,
  "useNewPage": true,
  "defaultVersion": "hmos-next-dp1",
  "searchFilter": {
    "labelVersionTitle": "版本",
    "showLabelVersion": true,
    "labelContentTitle": "产品/语言",
    "showLabelContent": true
  },
  "resourceAssets": {
    "rootPath": "/config/commonResource/",
    "zorroIconsPath": "zorroIcons/11.2.0/",
    "ckeditorPath": "aci-ck4/4.18.0/assets/article/aui-ckeditor.js",
    "highligthPath": "highlight/11.9.0",
    "highligth8Path": "aci-ck4/4.18.0/assets/article/plugins/codesnippet/lib/highlight",
    "hwplayerLibPath": "hwplayer",
    "pdfjsPath": "pdfjsToDoc/pdf",
    "pluginsPath": "plugins/1.0/",
    "hianalyticsPath": "hianalytics/2.2.1.501"
  },
  "$wxServe": {
  'wxAppid': 'wx8dbf6f625b6b9a9c'
}
,
  "notUpdate": [
    "agreement-0000001052728169",
    "merchantserviceagreement-0000001052848245",
    "partnerpaidserviceagreement-0000001052728251",
    "teamaccountprivacynotice-0000001053128239",
    "shfw-0000001219834413",
    "zfys-0000001219632939",
    "glzx-0000001174393188",
    "pssa-0000001227771181"
  ],
  "$cdnConfig": {
  'isOpen': true,
  'list': [
    {
      'originalUrl': 'communityfile-drcn.op.hicloud.com',
      'cdnUrl': 'alliance-communityfile-drcn.dbankcdn.com'
    },
    {
      'originalUrl': 'appfile-cn.dbankcdn.com',
      'cdnUrl': 'appfile1.hicloud.com'
    },
    {
      'originalUrl': 'communityfile-drcn.op.dbankcloud.cn',
      'cdnUrl': 'alliance-communityfile-drcn.dbankcdn.com'
    }
  ]
}
,
  "historylength": 50,
  "twitterAccount": "Huawei_devs",
  "baseLanPrefix": 1,
  "websiteType": 1,
  "websiteForRemark": 1,
  "$auiDataUrl": {
  'cn': 'https://developer.huawei.com/config/cn/head.json',
  'en': 'https://developer.huawei.com/config/en/head.json',
  'ru': 'https://developer.huawei.com/config/ru/head.json',
  'de': 'https://developer.huawei.com/config/de/head.json',
  'es': 'https://developer.huawei.com/config/es/head.json',
  'fr': 'https://developer.huawei.com/config/fr/head.json',
  'pt': 'https://developer.huawei.com/config/pt/head.json',
  'jp': 'https://developer.huawei.com/config/jp/head.json',
  'kr': 'https://developer.huawei.com/config/kr/head.json'
}
,
  "searchConfig": {
    "$searchUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/developer/search',
    "$getRecommendResourceUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/v1/servlet/recommend/getRecommendResource',
    "$hotwordsUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/developer/getAssociationalWords',
    "$recommendUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/developer/searchCard',
    "$topicInfoUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerforumservice/v1/open/getTopicInfo4Search',
    "$blogTopicInfoUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerblogservice/v1/openblog/getBlogInfo4Search',
    "$getAuthorInfoUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerforumservice/v1/open/getAuthorInfo',
    "$getForumNameUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerforumservice/v1/open/getSectionList',
    "$getBlogNameUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerblogservice/v1/openblog/getTechnologyList',
    "$getMarketCategoryUrl": 'https://svc-drcn.developer.huawei.com/partnerVectorServlet/market/product/productCategoryQuery',
    "$getBusinessTypeUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getBusinessTypeInfo',
    "$getCodelabCategoryUrl": 'https://svc-drcn.developer.huawei.com/consumer/partnerCodelabsService/v1/developer/codelabs/getByProductContentOfFilter',
    "hotwords": {
      "cn": [
        "HMS Core",
        "HUAWEI HiAI",
        "HUAWEI AR",
        "HUAWEI VR"
      ]
    },
    "menus": {
      "cn": [
        "all",
        "doc",
        "activity",
        "training",
        "forum",
        "market",
        "codelabs",
        "news",
        "blog",
        "subject"
      ],
      "en": [
        "all",
        "doc",
        "activity",
        "codelabs",
        "news"
      ],
      "ru": [
        "all",
        "doc",
        "activity"
      ]
    },
    "menusShop": {
      "doc": {
        "nextSubType": {
          "value": [
            "allDoc",
            "guide",
            "api",
            "code",
            "sdk"
          ]
        },
        "kitName": {
          "concatApi": true,
          "placeholder": "allKit",
          "params": {
            "channel": 1
          }
        }
      },
      "activity": {
        "nextSubType": {
          "value": [
            "allActivity",
            "activityYX",
            "activityDigix",
            "activityProgram"
          ]
        },
        "status": {
          "value": [
            "activityStatus",
            "activiting",
            "activited"
          ]
        },
        "sort": {
          "value": [
            "sortAll",
            "sortCTime"
          ]
        }
      },
      "codelabs": {
        "serviceType": {
          "isList": true,
          "concatApi": true,
          "placeholder": "allCategory"
        },
        "timestamp": {
          "value": [
            "timeAll",
            "timeDayHalf",
            "timeDay",
            "timeWeek",
            "timeMonth",
            "timeYearHalf",
            "timeYear"
          ],
          "effectApi": false
        },
        "sort": {
          "value": [
            "sortAll",
            "sortCTime"
          ]
        }
      },
      "forum": {
        "forumId": {
          "concatApi": true,
          "placeholder": "allSection"
        },
        "timestamp": {
          "value": [
            "timeAll",
            "timeDayHalf",
            "timeDay",
            "timeWeek",
            "timeMonth",
            "timeYearHalf",
            "timeYear"
          ],
          "effectApi": false
        },
        "sort": {
          "value": [
            "sortAll",
            "sortCTime",
            "sortUTime",
            "sortReply",
            "sortLike"
          ]
        }
      },
      "blog": {
        "forumId": {
          "concatApi": true,
          "placeholder": "allBlog"
        },
        "timestamp": {
          "value": [
            "timeAll",
            "timeDayHalf",
            "timeDay",
            "timeWeek",
            "timeMonth",
            "timeYearHalf",
            "timeYear"
          ],
          "effectApi": false
        },
        "sort": {
          "value": [
            "sortAll",
            "sortCTime"
          ]
        }
      },
      "market": {
        "subTypeStr": {
          "value": [
            "firstCategory"
          ]
        },
        "subTypeStr2": {
          "value": [
            "secondCategory"
          ]
        },
        "subType": {
          "value": [
            "accessAll",
            "accessSaaS",
            "accessApi",
            "accessHardware",
            "accessService",
            "accessServerless"
          ]
        },
        "official": {
          "value": [
            "supportAll",
            "supportSelf",
            "supportOther"
          ]
        },
        "sort": {
          "value": [
            "sortAll",
            "sortSale",
            "sortPrice",
            "sortRemark"
          ]
        }
      }
    },
    "showCount": 75,
    "categoryList": [
      1,
      3,
      4,
      8,
      10,
      11,
      12,
      13,
      15,
      16,
      19
    ],
    "$openSmartAssistant": true,
    "$disablingTrustlist": false,
    "$useSearchGate": true,
    "$usePartnerSearchService": false,
    "$isAiHomologous": true
  },
  "$pathInfo": 'https://svc-drcn.developer.huawei.com/partnerVectorServlet/video/v1/servlet/queryPathRelations',
  "$examInfo": 'https://svc-drcn.developer.huawei.com/partnerVectorServlet/video/v1/servlet/exam/getFloorExamList',
  "$courseInfo": 'https://svc-drcn.developer.huawei.com/partnerVectorServlet/video/v1/servlet/learning/getCourseList',
  "$trainVideoInfo": 'https://svc-drcn.developer.huawei.com/partnerVectorServlet/video/v1/servlet/learning/getCourseActivityInfo',
  "$codelabInfo": 'https://svc-drcn.developer.huawei.com/consumer/partnerCodelabsService/v1/developer/codelabs/queryCardInfoByCardId',
  "$videoUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/v1/servlet/getVodAssetUrlById',
  "$addTrainVideoPlayTimes": 'https://svc-drcn.developer.huawei.com/partnerVectorServlet/video/v1/servlet/videos/collect',
  "$tokenUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/v1/servlet/renewalVodAssetToken',
  "$getCardAssociationalWordsUrl": 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/partnerCommunityService/developer/getCardAssociationalWords',
  "$oAuthConfig": {
  'serverUrl': 'https://developer-drcn.op.hicloud.com/',
  'siteID_country': {
    '1': 'cn',
    '2': 'en',
    '3': 'en',
    '8': 'ru'
  },
  'fileServerUrl': {
    '1': 'https://communityfile-drcn.op.hicloud.com/FileServer/uploadFile',
    '2': 'https://communityfile-dra.op.hicloud.com/FileServer/uploadFile',
    '3': 'https://communityfile-dre.op.hicloud.com/FileServer/uploadFile',
    '8': 'https://communityfile-drru.op.hicloud.com/FileServer/uploadFile'
  },
  'userCenter': {
    'cn': 'https://id1.cloud.huawei.com/CAS/portal/userCenter/index.html?service=http://developer.huawei.com/consumer/cn/',
    'en': 'https://id5.cloud.huawei.com/CAS/portal/userCenter/index.html',
    'ru': 'https://id8.cloud.huawei.com/CAS/portal/userCenter/index.html'
  },
  'timeout': 90000
}
,
  "channelName": {
    "WeiXin": "89000001",
    "WeiBo": "89000002",
    "HDG": "89000011",
    "Codelabs": "89000013",
    "HDD": "89000014",
    "HSD": "89000015",
    "HDE": "89000016",
    "XiaoYuan1": "89000050",
    "XiaoYuan2": "89000051",
    "HeZuo1": "89000004",
    "HeZuo2": "89000005",
    "HeZuo3": "89000009",
    "HeZuo4": "89000054",
    "HeZuo5": "89000055",
    "HeZuo6": "89000056",
    "HeZuo7": "89000057",
    "HeZuo8": "89000058",
    "HeZuo9": "89000059",
    "HeZuo10": "89000061",
    "HeZuo11": "89000062",
    "HeZuo12": "89000063",
    "HeZuo13": "89000064",
    "HeZuo14": "89000065",
    "HeZuo15": "89000066",
    "HeZuo16": "89000067",
    "HeZuo17": "89000068",
    "HeZuo18": "89000069",
    "HeZuo19": "89000070",
    "HeZuo20": "89000071",
    "HeZuo21": "89000072",
    "HeZuo22": "89000073",
    "HeZuo23": "89000074",
    "HeZuo24": "89000075",
    "HeZuo25": "89000076",
    "HeZuo26": "89000077",
    "HeZuo27": "89000078",
    "HeZuo28": "89000079",
    "HeZuo29": "89000080",
    "HeZuo30": "89000081",
    "HeZuo31": "89000082",
    "HeZuo32": "89000083",
    "HeZuo33": "89000084",
    "HeZuo34": "89000085",
    "HeZuo35": "89000086",
    "HeZuo36": "89000087",
    "HeZuo37": "89000088",
    "HeZuo38": "89000089",
    "HeZuo39": "89000090",
    "HeZuo40": "89000091",
    "HeZuo41": "89000092",
    "HeZuo42": "89000093",
    "HeZuo43": "89000094",
    "HeZuo44": "89000095",
    "HeZuo45": "89000096",
    "HeZuo46": "89000097",
    "HeZuo47": "89000098",
    "HeZuo48": "89000099",
    "HeZuo49": "89000200",
    "HeZuo50": "89000201",
    "HeZuo51": "89000202",
    "HeZuo52": "89000203",
    "HeZuo53": "89000204",
    "HeZuo54": "89000205",
    "HeZuo55": "89000206",
    "HeZuo56": "89000207",
    "HeZuo57": "89000208",
    "HeZuo58": "89000209",
    "HeZuo59": "89000210",
    "HeZuo60": "89000211",
    "HeZuo61": "89000212",
    "HeZuo62": "89000213",
    "HeZuo63": "89000214",
    "HeZuo64": "89000215",
    "HeZuo65": "89000216",
    "HeZuo66": "89000217",
    "HeZuo67": "89000218",
    "HeZuo68": "89000219",
    "HeZuo69": "89000220",
    "HeZuo70": "89000221",
    "HeZuo71": "89000222",
    "HeZuo72": "89000223",
    "HeZuo73": "89000224",
    "HeZuo74": "89000225",
    "HeZuo75": "89000226",
    "HeZuo76": "89000227",
    "HeZuo77": "89000228",
    "HeZuo78": "89000229",
    "HeZuo79": "89000230",
    "HeZuo80": "89000231",
    "Homepage": "89000100",
    "TeamAccout": "89000101",
    "VideoCenter": "89000102",
    "SocialMedia": "89000103",
    "Forum": "89000104",
    "Reserve1": "89000105",
    "Reserve2": "89000106",
    "HuoDong1": "89000107",
    "HuoDong2": "89000108",
    "HuoDong3": "89000109",
    "HuoDong4": "89000110",
    "HuoDong5": "89000111",
    "HuoDong6": "89000112",
    "HuoDong7": "89000113",
    "HuoDong8": "89000114",
    "HuoDong9": "89000115",
    "HuoDong10": "89000116",
    "HuoDong11": "89000117",
    "HuoDong12": "89000118",
    "HuoDong13": "89000119",
    "HuoDong14": "89000120",
    "HuoDong15": "89000121",
    "HuoDong16": "89000122",
    "HuoDong17": "89000123",
    "HuoDong18": "89000124",
    "HuoDong19": "89000125",
    "HuoDong20": "89000126",
    "HuoDong21": "89000127",
    "HuoDong22": "89000128",
    "HuoDong23": "89000129",
    "HuoDong24": "89000130",
    "HuoDong25": "89000131",
    "HuoDong26": "89000132",
    "HuoDong27": "89000133",
    "HuoDong28": "89000134",
    "HuoDong29": "89000135",
    "HuoDong30": "89000136",
    "HuoDong31": "89000137",
    "HuoDong32": "89000138",
    "HuoDong33": "89000139",
    "HuoDong34": "89000140",
    "HuoDong35": "89000141",
    "HuoDong36": "89000142",
    "HuoDong37": "89000143",
    "HuoDong38": "89000144",
    "HuoDong39": "89000145",
    "HuoDong40": "89000146",
    "HuoDong41": "89000147",
    "HuoDong42": "89000148",
    "HuoDong43": "89000149",
    "HuoDong44": "89000150",
    "HuoDong45": "89000151",
    "HuoDong46": "89000152",
    "HuoDong47": "89000153",
    "HuoDong48": "89000154",
    "HuoDong49": "89000155",
    "HuoDong50": "89000156",
    "HuoDong51": "89000157",
    "HuoDong52": "89000158",
    "HuoDong53": "89000159",
    "HuoDong54": "89000160",
    "HuoDong55": "89000161",
    "HuoDong56": "89000162",
    "HuoDong57": "89000163",
    "HuoDong58": "89000164",
    "HuoDong59": "89000165",
    "HuoDong60": "89000166"
  },
  "$apm_config": {
  'setTrackerUrl': 'https://metrics-drcn.dt.hicloud.com/webv2',
  'BySiteid': false,
  'setTrackerUrlBySiteid': {
    '1': 'https://metrics-drcn.dt.hicloud.com/webv2',
    '2': 'https://metrics-dra.dt.hicloud.com:6447/webv2',
    '3': 'https://metrics2.data.hicloud.com:6447/webv2',
    '8': 'https://metrics5.data.hicloud.com:6447/webv2'
  },
  'siteID_country': [
    {
      'siteid': 1,
      'lang': [
        'cn'
      ]
    },
    {
      'siteid': 8,
      'lang': [
        'ru'
      ]
    },
    {
      'siteid': 3,
      'lang': [
        'en',
        'de',
        'es',
        'fr',
        'pt'
      ]
    },
    {
      'siteid': 2,
      'lang': [
        'jp',
        'kr'
      ]
    }
  ],
  'apmEnable': true
}
,
  "$hajssdk_config": {
  'setTrackerUrl': 'https://metrics-drcn.dt.hicloud.com/webv2',
  'BySiteid': false,
  'setTrackerUrlBySiteid': {
    '1': 'https://metrics-drcn.dt.hicloud.com/webv2',
    '2': 'https://metrics-dra.dt.hicloud.com:6447/webv2',
    '3': 'https://metrics2.data.hicloud.com:6447/webv2',
    '8': 'https://metrics5.data.hicloud.com:6447/webv2'
  },
  'siteID_country': [
    {
      'siteid': 1,
      'lang': [
        'cn'
      ]
    },
    {
      'siteid': 8,
      'lang': [
        'ru'
      ]
    },
    {
      'siteid': 3,
      'lang': [
        'en',
        'de',
        'es',
        'fr',
        'pt'
      ]
    },
    {
      'siteid': 2,
      'lang': [
        'jp',
        'kr'
      ]
    }
  ],
  'setSiteId': 'developer.huawei.com/consumer',
  'eventType': 'CET000003',
  'eventTypeForUrl': 'CET000006',
  'sourceCode': 'SC000012',
  'location': '110002',
  'action': 'AC000003',
  'serviceItem': '998',
  'tagTypePageView': 'CMMT1001',
  'tagTypeAddVideoPlayTimes': 'CMMT0018',
  'Recommended': 'CMMT1085',
  'domain': 'official',
  '_pagesConfigs': {
    'detail': {
      'click_event': {
        'title': '',
        'cvarp': {
          'serviceItem': '998',
          'domain': 'official',
          'tagType': 'CMMT0002'
        }
      },
      'star_event': {
        'title': '文档中心评分',
        'cvarp': {
          'serviceItem': '998',
          'domain': 'official',
          'tagType': 'CMMT0003'
        }
      },
      'agreement': {
        'title': '',
        'cvarp': {
          '202': [
            'tagType',
            'CMMT0001'
          ],
          'serviceItem': '998',
          'domain': 'official',
          'tagType': 'CMMT0001',
          'clueExtendInfo': {
            'eventType': 'CET000004',
            'sourceCode': 'SC000012',
            'bizType': '',
            'location': '110001',
            'action': 'AC000004'
          }
        }
      },
      'attachment': {
        'title': '附件下载',
        'cvarp': {
          '202': [
            'tagType',
            'CMMT0001'
          ],
          'serviceItem': '998',
          'domain': 'official',
          'tagType': 'CMMT0001'
        }
      },
      'barname': '根节点搜索'
    },
    'search': {
      'search_event': {
        'all': 'CMMT0023',
        'doc': 'CMMT0010',
        'API': 'CMMT0010',
        'guides': 'CMMT0010',
        'sample': 'CMMT0010',
        'faq': 'CMMT0010',
        'training': 'CMMT0030',
        'forum': 'CMMT1061',
        'activity': 'CMMT0031',
        'codelabs': 'CMMT0029',
        'news': 'CMMT0032',
        'blog': 'CMMT1079',
        'subject': 'CMMT0041',
        'market': 'CMMT0044'
      },
      'click_event': {
        'all': 'CMMT0035',
        'doc': 'CMMT0036',
        'API': 'CMMT0036',
        'guides': 'CMMT0036',
        'sample': 'CMMT0036',
        'faq': 'CMMT0036',
        'training': 'CMMT0038',
        'forum': 'CMMT1080',
        'activity': 'CMMT0037',
        'codelabs': 'CMMT0039',
        'news': 'CMMT0040',
        'blog': 'CMMT1081',
        'subject': 'CMMT0042',
        'market': 'CMMT0045'
      },
      'barname': '统一搜索'
    }
  },
  'linker': {
    'domains': [
      'developer.harmonyos.com',
      'www.harmonyos.com',
      'device.harmonyos.com'
    ],
    'exclude': []
  }
}
,
  "FeedbackUrl": {
    "cn": "/consumer/cn/support/feedback",
    "en": "/consumer/en/support/feedback",
    "ru": "/consumer/ru/support/feedback"
  },
  "$verifyRealUrl": {
  'cn': 'https://developer.huawei.com/consumer/cn/devunion/openPlatform/html/handleLogin.html?&isEnrollment=true',
  'en': 'https://developer.huawei.com/consumer/en/openPlatformN/html/handleLogin.html?&isEnrollment=true',
  'ru': 'https://developer.huawei.com/consumer/ru/openPlatformN/html/handleLogin.html?&isEnrollment=true'
}
,
  "$myCustomerUrl": {
  'cn': 'https://developer.huawei.com/consumer/cn/support/feedback/#/',
  'en': 'https://developer.huawei.com/consumer/en/support/feedback/#/',
  'ru': 'https://developer.huawei.com/consumer/ru/support/feedback/#/'
}
,
  "$AICustomerUrl": {
  'cn': 'https://developer.huawei.com/consumer/cn/customerService/#/bot-dev-top/faq-top/faq-talk-top',
  'en': 'https://developer.huawei.com/consumer/en/customerService/#/bot-dev-top/faq-top/faq-talk-top',
  'ru': 'https://developer.huawei.com/consumer/ru/customerService/#/bot-dev-top/faq-top/faq-talk-top'
}
,
  "$consultationUrl": {
  'cn': 'https://developer.huawei.com/consumer/cn/consultation?source=document'
}
,
  "$forumUrl": {
  'cn': 'https://developer.huawei.com/consumer/cn/forum/',
  'en': 'https://forums.developer.huawei.com/forumPortal/en/home',
  'ru': 'https://forums.developer.huawei.com/forumPortal/en/home'
}
,
  "$myActivityUrl": {
  'cn': 'https://developer.huawei.com/consumer/cn/activity/myActivity',
  'en': 'https://developer.huawei.com/consumer/en/activity/myActivity',
  'ru': 'https://developer.huawei.com/consumer/ru/activity/myActivity'
}
,
  "$agreementURL": {
  'cn': 'https://developer.huawei.com/consumer/cn/devservice/term',
  'en': 'https://developer.huawei.com/consumer/en/devservice/term',
  'ru': 'https://developer.huawei.com/consumer/ru/devservice/term'
}
,
  "$iframeWhiteList": ['https://developer.huawei.com','https://www.harmonyos.com','https://device.harmonyos.com','https://developer.harmonyos.com'],
  "$originUrl": 'https://developer.huawei.com/',
  "nodeUseUrl": "https://developer.huawei.com/",
  "nodeHTMLCache": {
    "max": 1000,
    "maxAge": 3600000,
    "MAX_CONCURRENCY": 0,
    "isopen": false
  },
  "$HOSTED_VIEWER_ORIGINS": ['https://developer.huawei.com'],
  "pdf_frame_whiteList": [
    "https://terms-drcn.platform.hicloud.com",
    "https://terms-dre.platform.hicloud.com",
    "https://terms-drru.platform.hicloud.com",
    "https://terms-drcn.platform.dbankcloud.cn",
    "https://terms-dra.platform.dbankcloud.cn",
    "https://terms-drru.platform.dbankcloud.cn",
    "https://terms-dre.platform.dbankcloud.cn"
  ],
  "langMap": {
    "cn": "zh_cn",
    "en": "en_us",
    "ru": "ru_ru"
  },
  "geryNameList": [
    "630086000000306219"
  ],
  "$cookieDomain": 'developer.huawei.com',
  "$auiConfig": {
  'libHash': 'hashdsa870c',
  'trustDomainUrl': 'https://developer.huawei.com/config/trustDomain.json',
  'bianalytic': {
    'trackerUrl': 'https://metrics-drcn.dt.hicloud.com/webv2',
    'siteUrl': 'developer.huawei.com/consumer',
    'domain': 'official',
    'serviceItem': '910'
  },
  'site': {
    'china': '1',
    'european': '3',
    'singapore': '2',
    'russia': '8'
  },
  'oAuthConfig': {
    'isRecordLogin': true,
    'registerClientType': '89',
    'registerTimeRange': 300,
    'regUrl': 'https://id1.cloud.huawei.com/CAS/portal/userRegister/regbyemail.html',
    'loginURL': 'https://oauth-login.cloud.huawei.com/oauth2/v2/authorize',
    'logoutURL': 'https://oauth-login.cloud.huawei.com/connect/v2/logout',
    'getATUrl': 'https://svc-drcn.developer.huawei.com/codeserver',
    'servletURL': 'https://developer.huawei.com/consumer/',
    'serverUrl': 'https://svc-drcn.developer.huawei.com/',
    'codeServerURL': {
      '1': 'https://svc-drcn.developer.huawei.com/codeserver',
      '2': 'https://svc-dra.developer.huawei.com/codeserver',
      '3': 'https://svc-dre.developer.huawei.com/codeserver',
      '8': 'https://svc-drru.developer.huawei.com/codeserver'
    },
    'delegateURL': {
      '1': 'https://svc-drcn.developer.huawei.com/svc/community/common/v1/delegate'
    },
    'fileServerUrl': {
      '1': 'https://communityfile-drcn.op.hicloud.com/FileServer/uploadFile',
      '2': 'https://communityfile-dra.op.hicloud.com/FileServer/uploadFile',
      '3': 'https://communityfile-dre.op.hicloud.com/FileServer/uploadFile',
      '8': 'https://communityfile-drru.op.hicloud.com/FileServer/uploadFile'
    },
    'redirect_uri': {
      'cn': 'https://developer.huawei.com/devunion/openPlatform/refactor/handleLogin.html',
      'en': 'https://developer.huawei.com/consumer/en/login/html/handleLogin.html',
      'ru': 'https://developer.huawei.com/consumer/ru/login/html/handleLogin.html'
    },
    'siteID_country': {
      '1': 'cn',
      '2': 'en',
      '3': 'en',
      '8': 'ru'
    },
    'userCenter': {
      'cn': 'https://id1.cloud.huawei.com/CAS/portal/userCenter/index.html?service=http://developer.huawei.com/consumer/cn/',
      'en': 'https://id5.cloud.huawei.com/CAS/portal/userCenter/index.html',
      'ru': 'https://id8.cloud.huawei.com/CAS/portal/userCenter/index.html'
    },
    'clientID': '6099200',
    'loginChannel': '89000003',
    'reqClientType': '89',
    'timeout': 90000,
    'permissions': [
      'https://www.huawei.com/auth/account/country',
      'https://www.huawei.com/auth/account/base.profile'
    ],
    'handleLoginUrl': 'https://developer.huawei.com/aui2/handleLoginV2.html',
    'logoSize': 182,
    'mobLogoSize': 182
  }
}
,
  "isUseEditor": true,
  "agrTypeForLogin": 800,
  "accountAgrType": 800,
  "$onlineSite": ['1'],
  "$siteConfig": {
  'cn': {
    'siteid': [
      '1'
    ],
    'lang': [
      'cn'
    ],
    'servletUrl': 'https://svc-drcn.developer.huawei.com/community/servlet'
  },
  'eu': {
    'siteid': [
      '3'
    ],
    'lang': [
      'en',
      'de',
      'es',
      'fr',
      'pt'
    ],
    'servletUrl': 'https://svc-dre.developer.huawei.com/community/servlet'
  },
  'ru': {
    'siteid': [
      '8'
    ],
    'lang': [
      'ru'
    ],
    'servletUrl': 'https://svc-drru.developer.huawei.com/community/servlet'
  },
  'sg': {
    'siteid': [
      '2'
    ],
    'lang': [
      'jp',
      'kr'
    ],
    'servletUrl': 'https://svc-dra.developer.huawei.com/community/servlet'
  }
}
,
  "$defaultShareImageUrl": 'https://developer.huawei.com/system/modules/org.opencms.portal.template.core/resources/images/Huawei-LOGO.png',
  "useDocumentSearch": true,
  "$recommendResourceId": '101676877414319024',
  "customizedList": {
    "cn": [
      {
        "name": "我的收藏",
        "href": "/consumer/cn/personalcenter/myInfo/myCollection/document",
        "blank": true
      }
    ]
  },
  "atKeepAliveTimes": 3,
  "$diableApiCatalogNames": ['harmonyos-references-V1','atomic-references','harmonyos-references-V5','harmonyos-references-V13','harmonyos-references-V14'],
  "$disableDeviceTypeCatalogNames": [],
  "$trainingCompatible": false,
  "$reportUrl": 'https://developer.huawei.com/consumer/cn/report',
  "reportAppId": "50026",
  "myFeedbackUrl": "/consumer/cn/personalcenter/myInfo/myFeedback",
  "$showApplink": false,
  "$applinkConfig": {
  'appdownloadUrl': 'https://linking.developer.huawei.com/consumer/cn/appdownload/',
  'weakPage': {
    'allow': '/consumer/cn/activity',
    'notAllow': ''
  },
  'strongPage': {
    'allow': '/consumer/cn/forum',
    'notAllow': '/consumer/cn/forum/help'
  }
}
,
  "$newHeadSearch": true
}
})(window);
(function (window) {
  window.Ad_Type = {
    '-1': '其他-未分类',
    0: '内广-活动类',
    1: '内广-课程类',
    2: '内广-产品/服务类',
    3: '内广-人才/招聘类',
    4: '内广-技术分享/沙龙类',
    5: '（内部）相关推荐',
    6: '（内部）生态激励',
    7: '外广-活动类',
    8: '外广-课程类',
    9: '外广-产品/服务类',
    10: '外广-其他',
  };
})(window);
(function (window) {
  window.types = [
    'all',
    'doc',
    'API',
    'guides',
    'training',
    'forum',
    'activity',
    'programs',
    'codelabs',
    'page',
    'news',
    'blog',
    'plates',
    'subject',
    'sample',
    'cases',
    'component',
    'market',
    'thirdpart',
    'faq',
  ];
  window.typeCode = {
    all: 0,
    doc: 1,
    API: 1,
    guides: 1,
    training: 3,
    forum: 4,
    activity: 8,
    programs: 9,
    codelabs: 10,
    page: 11,
    news: 12,
    blog: 13,
    plates: 14,
    subject: 15,
    sample: 16,
    cases: 17,
    component: 18,
    thirdpart: 18,
    market: 19,
    // 各个菜单筛选值
    allDoc: 'NA',
    allHarmonyDoc: 'NA',
    allHarmonyKit: 'NA',
    allGuides: 'NA',
    developer: 1,
    device: 2,
    developmentGuide: 1,
    guide: 1,
    api: 2,
    code: 3,
    sdk: 4,
    design: 5,
    distribute: 6,
    allKit: 'NA',
    allLang: 'NA',
    ArkTS: 'ArkTS',
    java: 'Java',
    js: 'JS',
    c: 'C/C++',
    allForum: 'NA',
    allSection: 'NA',
    allCategory: 'NA',
    allBlog: 'NA',
    allActivity: 'NA',
    activityGeneral: 1,
    activityYX: 4,
    activityDigix: 5,
    activityProgram: 7,
    firstCategory: 'NA',
    secondCategory: 'NA',
    activityStatus: 'NA',
    activiting: 1,
    activited: 2,
    compDeveloper: 1,
    compDevice: 2,
    accessAll: 'NA',
    accessSaaS: 1,
    accessApi: 2,
    accessHardware: 3,
    accessService: 4,
    accessServerless: 5,
    supportAll: 'NA',
    supportSelf: 1,
    supportOther: 0,
    sortAll: 'NA',
    sortCTime: 1,
    sortUTime: 2,
    sortReply: 3,
    sortLike: 4,
    sortSale: [5, 6],
    sortPrice: [7, 8],
    sortRemark: [9, 10],
    timeAll: 'NA',
    timeDayHalf: 0.5,
    timeDay: 1,
    timeWeek: 7,
    timeMonth: 30,
    timeYearHalf: 182.5,
    timeYear: 365,
    faq: 1,
  };
})(window);
